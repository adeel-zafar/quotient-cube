require File.join(File.dirname(__FILE__), '..', '..', 'spec_helper')

describe QuotientCube::Tree::Base do
  describe "with the store, product, season data set" do
    before(:each) do
      @table = Table.new(
        :column_names => [
          'store', 'product', 'season', 'sales'
        ], :data => [
          ['S1', 'P1', 's', 6],
          ['S1', 'P2', 's', 12],
          ['S2', 'P1', 'f', 9]
        ]
      )
    
      @dimensions = ['store', 'product', 'season']
      @measures = ['sales[sum]', 'sales[avg]']
    
      @cube = QuotientCube::Base.build(
        @table, @dimensions, @measures
      ) do |table, pointers|
        sum = 0
        pointers.each do |pointer|
          sum += table[pointer]['sales']
        end
        
        [sum, sum / pointers.length.to_f]
      end
      
      @tempfile = Tempfile.new('database')
      @database = KyotoCabinet::DB.new
      @database.open(@tempfile.path, KyotoCabinet::DB::OWRITER | KyotoCabinet::DB::OCREATE)
      
      @tree = QuotientCube::Tree::Builder.build(@database, @cube, :prefix => 'prefix')
    end
    
    after(:each) do
      @database.close
    end
    
    it "should get a list of dimensions" do
      @tree.dimensions.should == ['store', 'product', 'season']
    end
    
    it "should get a list of measures" do
      @tree.measures.should == ['sales[sum]', 'sales[avg]']
    end
    
    it "should get a list of values" do
      @tree.values('store').should == ['S1', 'S2']
      @tree.values('product').should == ['P1', 'P2']
      @tree.values('season').should == ['f', 's']
    end
    
    it "should answer point and range queries" do
      @tree.find(:all).should == {'sales[sum]' => 27.0, 'sales[avg]' => 9.0}
      
      @tree.find('sales[avg]', 
        :conditions => {'product' => 'P1'}).should == {'product' => 'P1', 'sales[avg]' => 7.5}
      
      @tree.find('sales[avg]', 'sales[sum]').should == \
        {'sales[sum]' => 27.0, 'sales[avg]' => 9.0}
      
      @tree.find('sales[avg]', 
        :conditions => {'product' => 'P1', 'season' => 'f'}).should == \
          {'product' => 'P1', 'season' => 'f', 'sales[avg]' => 9.0}
      
      @tree.find('sales[avg]',
        :conditions => {'product' => ['P1', 'P2', 'P3']}).should == [
          {'product' => 'P1', 'sales[avg]' => 7.5}, 
          {'product' => 'P2', 'sales[avg]' => 12.0}
        ]
      
      @tree.find(:all, :conditions => {'product' => :all}).should ==   [
        {'product' => 'P1', 'sales[avg]' => 7.5, 'sales[sum]' => 15.0}, 
        {'product' => 'P2', 'sales[avg]' => 12.0, 'sales[sum]' => 12.0}
      ]
    end
  end
  
  describe "with the signup source data set" do
    before(:each) do
      @table = Table.new(
        :column_names => [
          'hour', 'user[source]', 'user[age]', 'event[name]', 'user[id]'
        ], :data => [
          ['340023', 'blog', 'NULL', 'signup', '1'],
          ['340023', 'blog', 'NULL', 'signup', '2'],
          ['340023', 'twitter', '14', 'signup', '3']
        ]
      )
    
      @dimensions = ['hour', 'user[source]', 'user[age]', 'event[name]']
      @measures = ['events[count]', 'events[percentage]', 'users[count]', 'users[percentage]']
    
      total_events = @table.length
      total_users = @table.distinct('user[id]').length
      
      @cube = QuotientCube::Base.build(
        @table, @dimensions, @measures
      ) do |table, pointers|
        events_count = pointers.length
        events_percentage = (events_count / total_events.to_f) * 100
        
        users = Set.new
        pointers.each do |pointer|
          users << @table[pointer]['user[id]']
        end
        
        users_count = users.length
        users_percentage = (users_count / total_users.to_f) * 100
        
        [events_count, events_percentage, users_count, users_percentage]
      end
      
      @tempfile = Tempfile.new('database')
      @database = KyotoCabinet::DB.new
      @database.open(@tempfile.path, KyotoCabinet::DB::OWRITER | KyotoCabinet::DB::OCREATE)
      
      @tree = QuotientCube::Tree::Builder.build(@database, @cube)
    end
    
    after(:each) do
      @database.close
    end
    
    it "should have the correct meta data" do
      @tree.dimensions.should == ['hour', 'user[source]', 'user[age]', 'event[name]']
      @tree.measures.should == ['events[count]', 'events[percentage]', 'users[count]', 'users[percentage]']
      @tree.values('hour').should == ['340023']
      @tree.values('user[source]').should == ['blog', 'twitter']
      @tree.values('user[age]').should == ['14', 'NULL']
      @tree.values('event[name]').should == ['signup']
    end
  
    it "should answer various queries" do
      @tree.find(:all, :conditions => {'hour' => ['3400231']}).should == []
      @tree.find(:all, :conditions => {'hour' => '3400231'}).should == nil
      @tree.find(:all, :conditions => {'event[name]' => 'fake'}).should == nil
      @tree.find(:all, :conditions => {'event[name]' => ['fake1', 'fake2']}).should == []
      
      @tree.find(:all, :conditions => {'hour' => '340023'}).should == {
        'hour' => '340023',
        'events[count]' => 3, 'events[percentage]' => 100.0,
        'users[count]' => 3, 'users[percentage]' => 100.0
      }
      
      @tree.find(:all, :conditions => \
        {'hour' => ['340023']}).should == [{
          'hour' => '340023','events[count]' => 3, 
          'events[percentage]' => 100.0,'users[count]' => 3, 
          'users[percentage]' => 100.0
      }]
      
      @tree.find(:all, :conditions => \
        {'event[name]' => 'signup'}).should == {
          'event[name]' => 'signup', 'events[count]' => 3, 
          'events[percentage]' => 100.0, 'users[count]' => 3, 
          'users[percentage]' => 100.0
        }
      
      @tree.find(:all, :conditions => \
        {'event[name]' => ['signup']}).should == [{
          'event[name]' => 'signup',
          'events[count]' => 3, 'events[percentage]' => 100.0,
          'users[count]' => 3, 'users[percentage]' => 100.0
        }]
      
      @tree.find(:all, :conditions => \
        {'hour' => :all}).should == [{
          'hour' => '340023', 'events[count]' => 3, 
          'events[percentage]' => 100.0, 'users[count]' => 3, 
          'users[percentage]' => 100.0
        }]
      
      @tree.find(:all, :conditions => \
        {'event[name]' => :all}).should == [{
          'event[name]' => 'signup', 'events[count]' => 3, 
          'events[percentage]' => 100.0, 'users[count]' => 3, 
          'users[percentage]' => 100.0
        }]
      
      @tree.find('events[count]', :conditions => {
        'user[age]' => '14', 'event[name]' => 'signup'
      }).should == {'user[age]' => '14', 'event[name]' => 'signup', 'events[count]' => 1.0}
      
      @tree.find('events[count]', :conditions => {
        'user[age]' => '14', 'event[name]' => 'fake'
      }).should == nil
      
      @tree.find(:all).should == {
        'events[count]' => 3, 'events[percentage]' => 100.0,
        'users[count]' => 3, 'users[percentage]' => 100.0
      }
            
      value = @tree.find('events[percentage]', 
                :conditions => {'user[source]' => 'twitter'})
      
      value.key?('events[percentage]').should == true
      (value['events[percentage]'] * 100).to_i.should == 3333
      
      @tree.find('users[count]', 
        :conditions => {'user[age]' => 'NULL'}).should == \
          {'user[age]' => 'NULL', 'users[count]' => 2.0}
      
      @tree.find('users[count]', 
        :conditions => {'user[age]' => :all}).should == [
          {'user[age]' => '14', 'users[count]' => 1.0},
          {'user[age]' => 'NULL', 'users[count]' => 2.0}
        ]
    end
  end
  
  describe "with only one row" do
    before(:each) do
      @table = Table.new(
        :column_names => [
          'hour', 'user[source]', 'user[age]', 'event[name]', 'user[id]'
        ], :data => [
          ['340023', 'blog', 'NULL', 'signup', '1'],
        ]
      )
    
      @dimensions = ['hour', 'user[source]', 'user[age]', 'event[name]']
      @measures = ['events[count]', 'events[percentage]', 'users[count]', 'users[percentage]']
    
      total_events = @table.length
      total_users = @table.distinct('user[id]').length
      
      @cube = QuotientCube::Base.build(
        @table, @dimensions, @measures
      ) do |table, pointers|
        events_count = pointers.length
        events_percentage = (events_count / total_events.to_f) * 100
        
        users = Set.new
        pointers.each do |pointer|
          users << @table[pointer]['user[id]']
        end
        
        users_count = users.length
        users_percentage = (users_count / total_users.to_f) * 100
        
        [events_count, events_percentage, users_count, users_percentage]
      end
  
      @tempfile = Tempfile.new('database')
      @database = KyotoCabinet::DB.new
      @database.open(@tempfile.path, KyotoCabinet::DB::OWRITER | KyotoCabinet::DB::OCREATE)
      
      @tree = QuotientCube::Tree::Builder.build(@database, @cube, :prefix => 'prefix')
    end
  
    after(:each) do
      @database.close
    end
    
    it "should answer a variety of queries" do
      @tree.find(:all).should == {
        'events[count]' => 1, 'events[percentage]' => 100.0,
        'users[count]' => 1, 'users[percentage]' => 100.0
      }
      
      @tree.find('events[count]', :conditions => \
        {'hour' => :all}).should == [{'hour' => '340023', 'events[count]' => 1.0}]
      
      @tree.find('events[count]', :conditions => {'hour' => 'fake'}).should == nil
    end
  end
  
  describe "with the tiny hourly events data set" do
    before(:each) do
      base_table = load_fixture('tiny_hourly_events')
      
      @dimensions = ['day', 'hour', 'event[name]']
      @measures = ['events[count]']
      
      @cube = QuotientCube::Base.build(base_table, @dimensions, @measures) do |table, pointers|
        [pointers.length]
      end
      
      @tempfile = Tempfile.new('database')
      @database = KyotoCabinet::DB.new
      @database.open(@tempfile.path, KyotoCabinet::DB::OWRITER | KyotoCabinet::DB::OCREATE)
      
      @tree = QuotientCube::Tree::Builder.build(@database, @cube)
    end
    
    it "should answer various queries" do
      @tree.find(:all, :conditions => \
        {'event[name]' => 'signup', 'hour' => :all}).should == \
          [{"hour"=>"349205", "event[name]"=>"signup", "events[count]"=>2.0}, 
          {"hour"=>"349206", "event[name]"=>"signup", "events[count]"=>1.0}]
    end
  end
      
  describe "with fixed values at dimensions greater than the first" do
    before(:each) do
      @table = Table.new(
        :column_names => [
          'day', 'hour', 'event', 'source'
        ], :data => [
          ['1', '1', 'home', 'direct'],
          ['2', '3', 'home', 'NULL'],
          ['2', '4', 'time', 'NULL']
        ]
      )
      
      @dimensions = ['day', 'hour', 'event', 'source']
      @measures = ['events[count]']
      
      @cube = QuotientCube::Base.build(@table, @dimensions, @measures) do |table, pointers|
        [pointers.length]
      end
      
      @tempfile = Tempfile.new('database')
      @database = KyotoCabinet::DB.new
      @database.open(@tempfile.path, KyotoCabinet::DB::OWRITER | KyotoCabinet::DB::OCREATE)
      
      @tree = QuotientCube::Tree::Builder.build(@database, @cube)
    end
    
    after(:each) do
      @database.close
    end
    
    it "should do some queries" do        
      @tree.find(:all, :conditions => \
        {'event' => 'time', 'day' => :all}).should == \
          [{"day"=>"2", "event"=>"time", "events[count]"=>1.0}]

      @tree.find(:all, :conditions => \
        {'event' => 'home', 'day' => :all}).should == \
          [{"day" => "1", "event" => "home", "events[count]" => 1.0},
            {"day" => "2", "event" => "home", "events[count]" => 1.0}]
    end
  end
  
  describe "The hardest bug to find ever" do
    before(:each) do
      @table = Table.new(
        :column_names => [
          'day', 'hour', 'event', 'source'
        ], :data => [
          ['day2', 'hour3', 'home', 'NULL'],
          ['day2', 'hour4', 'home', 'NULL'],
          ['day2', 'hour4', 'time', 'NULL']
        ]
      )
      
      @dimensions = ['day', 'hour', 'event', 'source']
      @measures = ['events[count]']
      
      @cube = QuotientCube::Base.build(@table, @dimensions, @measures) do |table, pointers|
        [pointers.length]
      end
            
      @tempfile = Tempfile.new('database')
      @database = KyotoCabinet::DB.new
      @database.open(@tempfile.path, KyotoCabinet::DB::OWRITER | KyotoCabinet::DB::OCREATE)
      @tree = QuotientCube::Tree::Builder.build(@database, @cube)
    end
    
    it "should answer the one query that matters" do
      @tree.find(:all, :conditions => \
        {'event' => 'time', 'day' => :all}).should == \
          [{"day"=>"day2", "event"=>"time", "events[count]"=>1.0}]
    end
    
    it "should answer this other hard range query" do
      @tree.find(:all, :conditions => \
        {'event' => ['home', 'time']}).should == \
          [{'event' => 'home', 'events[count]' => 2.0}, 
          {'event' => 'time', 'events[count]' => 1.0}]
    end
  end
end