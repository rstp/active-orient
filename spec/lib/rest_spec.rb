
require 'spec_helper'
require 'rest_helper'


shared_examples_for 'a valid Class' do

end
describe ActiveOrient::OrientDB do

  #  let(:rest_class) { (Class.new { include HCTW::Rest } ).new }

  before( :all ) do
    reset_database
  end


  context "check private methods", :private do
    ## uris are  not used any more
#    it 'simple_uris' do
#      expect( ORD.property_uri('test')).to eq "property/#{@database_name}/test"
#      expect( ORD.command_sql_uri ).to eq "command/#{@database_name}/sql/"
#      expect( ORD.query_sql_uri ).to eq "query/#{@database_name}/sql/"
#      expect( ORD.database_uri ).to eq "database/#{@database_name}"
#      expect( ORD.document_uri ).to eq "document/#{@database_name}"
#      expect( ORD.class_uri ).to eq "class/#{@database_name}"
#      expect( ORD.class_uri {'test'} ).to eq "class/#{@database_name}/test"
#
#    end
#
    context  "translate property_hash"  do
      it "simple property" do
        ph= { :type => :string }
        field = 't'
        expect( ORD.translate_property_hash field , ph ).to eq  field => {:propertyType=>"STRING"}
      end
      it "simple property with linked_class" do
        ORD.create_class :Contract
        ph= { :type => :link, linked_class: 'Contract' }
        field = 't'
        expect( ORD.translate_property_hash field , ph ).to eq  field => {:propertyType=>"LINK", :linkedClass=>"Contract"}
      end

      it 'primitive property definition' do
        ph= {:propertyType=>"STRING" }
        field = 't'
        expect( ORD.translate_property_hash field , ph ).to eq  field => {:propertyType=>"STRING"}
        ph= {:propertyType=> :string}
        expect( ORD.translate_property_hash field , ph ).to eq  field => {:propertyType=>"STRING"}
        ph= {:propertyType=> 'string'}
        expect( ORD.translate_property_hash field , ph ).to eq  field => {:propertyType=>"STRING"}
      end
      it 'primitive property definition with linked_class' do
        ph= {:propertyType=>"STRING", linked_class: :Contract }
        field = 't'
        expect( ORD.translate_property_hash field , ph ).to eq  field => {:propertyType=>"STRING", :linkedClass=>:Contract}
        ph= {:propertyType=> :string, linkedClass: :Contract }
        expect( ORD.translate_property_hash field , ph ).to eq  field => {:propertyType=>"STRING", :linkedClass=>:Contract }
      end
    end
  end
  context "establish a basic-auth ressource"   do
    it "connect " do
      expect( ORD.get_resource ).to be_a RestClient::Resource
      expect( ORD.connect ).to be_truthy
    end
  end


  describe "handle Properties at Class-Level"  do
    before(:all) do
      ORD.create_class  :Contract, :exchange, 'property', :industry
      Property.create_properties( 
				 symbol: { propertyType: 'STRING' },
				 con_id: { propertyType: 'INTEGER' } ,
				 exchanges: { propertyType: 'LINKLIST', linkedClass: :exchange } ,
				 details: { propertyType: 'LINK', linkedClass: :Contract },
				 date: { propertyType: 'DATE' }
				)
      
    end
#    before(:each){ ActiveOrient::Model::Property.delete_class; 	Property = DB.create_class 'property' }

    it "define some Properties on class Property" do

      ## count the number of defined properties 
#      expect( predefined_property ).to eq 5
      rp= ORD.get_class_properties(  Property )['properties']
      expect(rp.map{|y| y['name']}).to eq ["date", "symbol", "con_id", "exchanges", "details"]
    end
    it "define property with automatic index"   do
      c = ORD.create_class :contract_detail
      ORD.create_property( c, :con_id, type: :integer) { :unique }
      expect( ORD.get_class_properties(c)['indexes'] ).to have(1).item
      expect( ORD.get_class_properties(c)['indexes'].first).to eq(
	{	"name"=>"contract_detail.con_id", "type"=>"UNIQUE", "fields"=>["con_id"] } )
    end

    it "define a property with manual index" do
      rp = ORD.create_properties( Contract,
				 { symbol: { type: :string },
       con_id: { type: :integer } ,
       industry: { type: :link, linkedClass: 'industry' }  } ) do
	 { test_ind: :unique }
       end
       expect( ORD.get_class_properties(Contract)['indexes'] ).to have(1).item
       expect( ORD.get_class_properties(Contract)['indexes'].first).to eq(
	 {	"name"	  =>  "test_ind", 
		"type"	  =>  "UNIQUE", 
		"fields"  =>  ["symbol", "con_id", "industry"] } )
    end

    it "add a dataset"   do
      ## without predefined property the test fails because the date is recognized as string.
      linked_record = DB.create_record Industry, attributes:{ label: 'TestIndustry' }
      expect{ DB.upsert  Property,  where: { con_id: 12345 }, 
					set: { industry: linked_record.rid, 
					date: Date.parse( "2011-04-04") } 
	    }.to change{ Property.count }.by 1

      ds = Property.where con_id: 12345
      puts "PROPERTY:"
      puts ds.inspect
      expect( ds ).to be_a Array
      expect( ds.first ).to be_a ActiveOrient::Model
      expect( ds.first.con_id ).to eq 12345
      expect( ds.first.industry ).to eq linked_record
      expect( ds.first.date ).to be_a Date
    end


    it "manage  exchanges in a linklist " do

      f = Exchange.create :label => 'Frankfurt'
      b = Exchange.create :label => 'Berlin'
      s = Exchange.create :label => 'Stuttgart'
      ds =Property.create con_id: 12355
      ds.add_item_to_property :exchange , f,b,s      #	  ds.add_item_to_property :exchanges, b
      #	  ds.add_item_to_property :exchanges, s
      expect( ds.exchange ).to have(3).items
      expect( Property.custom_where( "'Stuttgart' in exchange.label").first ).to eq ds
      expect( Property.custom_where( "'Hamburg' in exchange.label") ).to  be_empty
      ds.remove_item_from_property :exchange, b,s 
      expect( ds.exchange ).to have(1).items
    end

   it "add  an embedded linkmap- entry " do # , :pending => true do
#      pending( "Query Database for last entry does not work in 2.2" )
      property_record=  Property.create  con_id: 12346, property: []
      industries =  ['Construction','HealthCare','Bevarage']
      industries.each{| industry | property_record.property <<  Industry.create( label: industry ) }
      # to query: select * from Property where 'Stuttgart' in exchanges.label
      # or select * from Property where exchanges contains ( label = 'Stuttgart' )
      #
      expect( property_record.property.label ).to eq industries 

      pr =  Property.custom_where( "'HealthCare' in property.label").first
      expect( pr ).to eq property_record

      expect( property_record.con_id ).to eq 12346
      expect( property_record.property ).to be_a Array
      expect( property_record.property ).to have(3).records
      expect( property_record.property.last ).to eq Industry.last

      expect( property_record.property[2].label ).to eq industries[2]
      expect( property_record.property.label[2] ).to eq industries[2]
      expect( property_record.property.find{|x| x.label == 'HealthCare'}).to be_a Industry


    end

    ## rp['properties'] --> Array of
    #  {"name" => "exchanges", "linkedClass" => "Exchange",
    #   "type" => "LINKMAP", "mandatory" => false, "readonly" => false,
    #   "notNull" => false, "min" => nil, "max" => nil, "regexp" => nil,
    #   "collate" => "default"}
    #
    # disabled for now
    #     it "a new record is initialized with preallocated properties" do
    #	new_record =  Property.create
    #	DB.get_class_properties(  Property )['properties'].each do | property |
    #	  expect( new_record.attributes.keys ).to include property['name']
    #
    #	end

    #      end

  end

  context "Update a record" do
          before(:all) do
	    ORD.create_class 'this_test'
	    @the_record =  ThisTest.create a: 15
	  end

          it "create a simple record" do
	    expect( @the_record.a).to eq 15
	  end

          it "modify the attribute direct" do
	    @the_record.a = 20
	    expect( @the_record.a).to eq 20
	  end
	  
	  it "reread the unchanged data  from the database" do
	    expect( ORD.get_record( @the_record.rid).a).to eq 15 
	  end

	  it "perform REST-Update" do
	    json_hash = ORD.update @the_record.rid, {a: 25} 
	    expect( json_hash['a'] ).to eq 25
	  end
  end
end
=begin
          it "get a document through the query-class" , focus: true do
            r=  ORD.create_document  ORDest_class, attributes: { con_id: 343, symbol: 'EWTZ' }
            expect( @query_class.get_documents ORDest_class, where: { con_id: 343, symbol: 'EWTZ' }).to eq 1
            expect( @query_class.records ).not_to be_empty
            expect( @query_class.records.first ).to eq r
            expect( @query_class.queries ).to have(1).record
            expect( @query_class.queries.first ).to eq "select from Documebntklasse10 where con_id = 343 and symbol = 'EWTZ'"

          end

          #    it "execute a query from stack" , do
          #     # get_documents saved the query
          #      # we execute this once more
          #       @query_class.reset_results
          #       expect( @query_class.records ).to be_empty
          #
          #       expect{ @query_class.execute_queries }.to change { @query_class.records.size }.to 1
          #
          #    end

        end

        context "execute batches"  do
          it "a simple batch" do
            ORD.delete_class 'Person'
            ORD.delete_class 'Car'
            ORD.delete_class 'Owns'
            res = ORD.execute  transaction: false do
              ## perform operations from the tutorial
              sql_cmd = -> (command) { { type: "cmd", language: "sql", command: command } }

              [ sql_cmd[ "create class Person extends V" ] ,
              sql_cmd[ "create class Car extends V" ],
              sql_cmd[ "create class Owns extends E"],

              sql_cmd[ "create property Owns.out LINK Person "],
              sql_cmd[ "create property Owns.in LINK Car "],
              sql_cmd[ "alter property Owns.out MANDATORY=true "],
              sql_cmd[ "alter property Owns.in MANDATORY=true "],
              sql_cmd[ "create index UniqueOwns on Owns(out,in) unique"],

              { type: 'c', record: { '@class' => 'Person' , name: 'Lucas' } },
              sql_cmd[ "create vertex Person set name = 'Luca'" ],
              sql_cmd[ "create vertex Car set name = 'Ferrari Modena'"],
              { type: 'c', record: { '@class' => 'Car' , name: 'Lancia Musa' } },
              sql_cmd[ "create edge Owns from (select from Person where name='Luca') to (select from Car where name = 'Lancia Musa')" ],
              sql_cmd[ "create edge Owns from (select from Person where name='Lucas') to (select from Car where name = 'Ferrari Modena')" ],
              sql_cmd[ "select name from ( select expand( out('Owns') ) from Person where name = 'Luca' )" ]
            ]
          end
          # the expected result: 1 dataset, name should be Ferrari
          expect( res).to be_a Array
          expect( res.size ).to eq 1
          expect( res.first.name).to eq  'Lancia Musa'
          expect( res.first).to be_a ActiveOrient::Model::Myquery

        end

      end
      # this must be the last test in file because the database itself is destroyed
      context "create and destroy a database" do


        it "list all databases" do
          # the temp-database is always present
          databases =  ORD.get_databases
          expect( databases ).to be_a Array
          expect( databases ).to include 'temp'

        end

        it "create a database" do
          newDB = 'newTestDatabase'
          r =  ORD.create_database database: newDB
          expect(r).to eq newDB
        end

        it "delete a database"  do

          rmDB = 'newTestDatabase'
          r = ORD.delete_database database: rmDB
          expect( r ).to be_truthy
        end
      end

=end


    # response ist zwar ein String, verfügt aber über folgende Methoden
    # :to_json
    # :to_json_with_active_support_encoder,
    # :to_json_without_active_support_encoder,
    # :as_json,
    # :to_crlf
    # :to_lf
    # :to_nfc,
    # :to_nfd,
    # :to_nfkc,
    # :to_nfkd,
    # :to_json_raw,
    # :to_json_raw_object,
    # :valid_encoding?,
    # :request,
    # :net_http_res,
    # :args,
    # :headers,
    # :raw_headers,
    # :cookies,
    # :cookie_jar,
    # :description,
    # :follow_redirection,
    # :follow_get_redirection,
    #
