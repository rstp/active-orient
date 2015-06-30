
require 'spec_helper'
require 'active_support'

module REST
  class Base
    def self.get_riid
      @@rid_store
    end
  end
end

describe REST::Model do
  before( :all ) do

    # working-database: hc_database
    REST::Base.logger = Logger.new('/dev/stdout')

    @r= REST::OrientDB.new database: 'hc_database' , :connect => false
    REST::Model.orientdb  =  @r
    @r.delete_class 'modeltest'
    @testmodel = @r.create_class "modeltest" 
    @myedge = @r.create_edge_class name: 'Myedge'
  end

  context "REST::Model classes got a logger and a database-reference" do
    
    subject { REST::Model.orientdb_class name: 'Test' }
    it{ is_expected.to be_a Class }
    its( :logger) { is_expected.to be_a Logger }
    its( :orientdb) { is_expected.to be_a REST::OrientDB }

    it "a Model-Instance inherents logger and db-reference" do
      object =  subject.new
      expect( object.logger ).to be_a Logger
      expect( object.orientdb ).to be_a REST::OrientDB
    end

    it "repeatedly instantiated Model-Objects are allocated once" do
      second =  REST::Model.orientdb_class name: 'Test' 
      expect( second).to eq subject
    end
  end


  context "Add a document to the class" do
    it "the database is empty before we start" do
      @r.get_documents o_class: @testmodel
      expect( @testmodel.count_documents ).to be_zero
    end

    it "create a document" do
      before   =  @testmodel.count_documents 
      new_document= @testmodel.new_document attributes: { test: 45} 
      after = @testmodel.count_documents   
      expect( before +1 ).to eq after

      expect(new_document).to be_a REST::Model::Modeltest
      expect(new_document.test).to eq 45
  
      expect( REST::Base.get_riid.values.detect{|x| x == new_document}).to be_truthy
    end  


    it "the document can be retrieved by all"  do
      all = @testmodel.all
      expect(all).to be_a Array
      expect(all.size).to eq 1
      expect(all.first).to  be_a REST::Model::Modeltest
      expect(all.first.test).to eq 45
    end

    it "the document can be updated" do
      obj =  @testmodel.all.first
      riid = REST::Base.get_riid
      obj.update set: { test: 76, new_entry: "This is a new Entry" }
      expect( obj.test ).to eq 76
      expect( obj.new_entry).to be_a String
      expect(REST::Base.get_riid).to eq riid  # the riid-store is updated as well!

    end

    it "the document can be deleted"  do
      obj =  @testmodel.all.first
      obj.delete
      expect( @testmodel.all).to be_empty
    end
  end
  context  "Links and Linksets are followed"  do
    before(:all) do 
      @r.delete_class  'Testlinkclass'
      @r.delete_class  'Testbaseclass'

      @link_class = @r.create_class 'Testlinkclass'
      @base_class = @r.create_class 'Testbaseclass'
      @base_class.create_property field: 'to_link_class', type: 'link', linked_class: @link_class
      @base_class.create_property field: 'a_link_set', type: 'linkset', linked_class: @link_class
    
    end

    it "create a link" , focus:true  do
     link_document =  @link_class.new_document attributes: { att: 'one attribute' } 
#     puts "rid:  #{link_document.rid}"
#     puts "riid: #{link_document.riid}"
#     puts REST::Base.get_riid[ link_document.riid].inspect
     base_document =  @base_class.new_document attributes: { base: 'my_base', to_link_class: link_document.link } 

     expect(base_document.to_link_class).to eq link_document
    end

    it "create a linkset", focus: true do

     base_document =  @base_class.new_document attributes: { base: 'my_base_with_linkset' } 
    (1..10).each  do |x|
      link_document =  @link_class.new_document attributes: { att: " #{x} attribute" } 
      base_document.update_linkset( :a_link_set, link_document )
    end
  
    # reload document
     reloaded_document =  @r.get_document base_document.rid
     expect( reloaded_document.a_link_set).to have(10).items
      expect( reloaded_document[:a_link_set].first).to be_a REST::Model
     reloaded_document[:a_link_set].each{|x| expect(x).to be_a REST::Model }
   #  expect(base_document.to_link_class).to eq link_document

    end
      

  end

  context "Operate with an embedded object" , focus: true do
    before(:all) do 
      @r.delete_class  'Testbaseclass'

      @base_class = @r.create_class 'Testbaseclass'
      @base_class.create_property field: 'to_data', type: 'embeddedlist', linked_class: 'FLOAT'
#      @base_class.create_property field: 'a_link_set', type: 'linkset', linked_class: @link_class
    
    end
    it "work with a schemaless approach" do
  
      emb = [1,2,"zu",1]
      base_document = @base_class.new_document attributes: { embedded_item: emb }
      expect(base_document.embedded_item).to eq emb

      base_document.update_embedded :embedded_item, " 45"
      expect(base_document.embedded_item).to eq emb << " 45"

      reloaded_document =  @r.get_document base_document.rid
      expect(reloaded_document.embedded_item).not_to eq emb
  
    end

    it "work with embeddedlist" do
      emb = [1,2,"zu",1]
      nbase_document = @base_class.new_document attributes: { to_data: emb }
      expect(nbase_document.to_data).to eq emb
      nbase_document.update_embedded :to_data, " 45"
      expect(nbase_document.to_data).to eq emb << " 45"

      reloaded_document =  @r.get_document nbase_document.rid
      expect(reloaded_document.to_data).not_to eq emb
      expect(reloaded_document.to_data).to eq [1,2,"zu",1,45]  # Orientdb convertes " 45" to a numeric
    end
  end


  context "ActiveRecord mimics"  , focus:true  do
    it "fetch all documents into an Array" do
      @testmodel.new_document attributes: { test: 45} 
      all_documents = @testmodel.all
      expect( all_documents ).to be_a Array #HashWithIndifferentAccess
      expect( all_documents ).to have_at_least(1).element
      all_documents.each{|x| expect(x).to be_a REST::Model }
    end

    it "get a set of documents queried by where"  do
      (1..45).each{|x| @testmodel.new_document :attributes => { test: x } }
      expect( @testmodel.count_documents ).to eq 46
      all_documents = @testmodel.all  ## all fetches only 20 records
#      puts all_documents.map( &:test).join(' .. ')
      nr_23=  @testmodel.where :attributes => { test: 23 }
      expect( nr_23 ).to have(1).element
      expect( nr_23.first.test).to eq 23

      expect( @testmodel.all.size).to eq  46


    end

    it "creates an edge between two documents" do
      out_e =  @r.update_or_create_documents( o_class: @testmodel, :where => { test: 23 } ).first 
      in_e  =  @r.update_or_create_documents( o_class: @testmodel, :where => { test: 15 } ).first 
      in_e2  = @r.update_or_create_documents( o_class: @testmodel, :where => { test: 16 } ).first 
      the_edge= @myedge.create_edge( 
			  attributes: { halbwertzeit: 45 }, 
			  from: out_e,
			  to:   in_e  )
      expect( the_edge).to be_a REST::Model
#      the_edge2= @myedge.create_edge( 
#			  attributes: { halbwertzeit: 46 }, 
#			  from: in_e,
#			  to:   in_e2  )
      expect( the_edge.out ).to eq out_e
      expect( the_edge.in ).to eq in_e
#      expect( the_edge2.out ).to eq in_e
#      expect( the_edge2.in ).to eq in_e2
      out_e =  @testmodel.where( :attributes => { test: 23 } ).first 
      expect( out_e.attributes).to include 'out_Myedge'
      in_e = @testmodel.where( :attributes => { test: 15 } ).first 
      expect( in_e.attributes).to include 'in_Myedge'
#      puts "in+out"
      puts in_e.inspect
#      puts out_e.inspect
#
      expect( in_e.myedge[0] ).to be_a REST::Model::Myedge
     puts in_e.myedge[0].inspect 
     puts  in_e.myedge[0].out.inspect
     expect( in_e.myedge[0].out.test).to eq 23
     expect( in_e.in_Myedge[0].in.test).to eq  15
    end

    it "deletes an edge"  do
      the_edges =  @myedge.all
      expect(the_edges.size).to  be >=1 

      the_edges.each do |edge|
	edge.delete
      end
      the_edges =  @myedge.all
      expect(the_edges.size).to  be_zero
    end

  end


end
