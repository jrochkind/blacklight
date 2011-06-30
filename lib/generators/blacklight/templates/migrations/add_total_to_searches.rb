# -*- encoding : utf-8 -*-
class AddTotalToSearches < ActiveRecord::Migration
  def self.up
    add_column :searches, :total, :int    
  end

  def self.down
    remove_column :searches, :total
  end
end
