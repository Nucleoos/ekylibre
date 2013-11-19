# = Informations
# 
# == License
# 
# Ekylibre - Simple ERP
# Copyright (C) 2009-2013 Brice Texier, Thibaud Merigon
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see http://www.gnu.org/licenses.
# 
# == Table: subscriptions
#
#  address_id        :integer          
#  created_at        :datetime         not null
#  creator_id        :integer          
#  description       :text             
#  first_number      :integer          
#  id                :integer          not null, primary key
#  last_number       :integer          
#  lock_version      :integer          default(0), not null
#  nature_id         :integer          
#  number            :string(255)      
#  product_nature_id :integer          
#  quantity          :decimal(19, 4)   
#  sale_id           :integer          
#  sale_item_id      :integer          
#  started_on        :date             
#  stopped_on        :date             
#  subscriber_id     :integer          
#  suspended         :boolean          not null
#  updated_at        :datetime         not null
#  updater_id        :integer          
#


class Subscription < Ekylibre::Record::Base
  acts_as_numbered
  # attr_accessible :address_id, :description, :first_number, :last_number, :started_on, :stopped_on, :suspended, :sale_item_id, :nature_id
  belongs_to :address, class_name: "EntityAddress"
  belongs_to :subscriber, class_name: "Entity"
  belongs_to :nature, class_name: "SubscriptionNature"
  belongs_to :product_nature
  belongs_to :sale
  belongs_to :sale_item, class_name: "SaleItem"
  #[VALIDATORS[ Do not edit these lines directly. Use `rake clean:validations`.
  validates_numericality_of :first_number, :last_number, allow_nil: true, only_integer: true
  validates_numericality_of :quantity, allow_nil: true
  validates_length_of :number, allow_nil: true, maximum: 255
  validates_inclusion_of :suspended, in: [true, false]
  #]VALIDATORS]
  validates_presence_of :started_on, :stopped_on, if: Proc.new{|u| u.nature and u.nature.period?}
  validates_presence_of :first_number, :last_number, if: Proc.new{|u| u.nature and u.nature.quantity?}
  validates_presence_of :nature, :subscriber
  validates_presence_of :sale_item, if: Proc.new{|s| !s.sale.nil?}, on: :create

  before_validation do
    self.sale_id      = self.sale_item.sale_id if self.sale_item
    self.address_id ||= self.sale.delivery_address_id if self.sale
    self.subscriber_id    = self.address.entity_id if self.address
    self.nature_id    = self.product_nature.subscription_nature_id if self.product_nature
    return true
  end

  before_validation(on: :create) do
    if self.nature
      if self.nature.period?
        if self.product_nature
          period = (self.product_nature.subscription_period.blank? ? '1 year' : self.product_nature.subscription_period)||'1 year'
        else
          period = '1 year'
        end
        #raise Exception.new "ok"+period.inspect+self.product.subscription_period.inspect
        self.started_on ||= Date.today
        self.stopped_on ||= Delay.compute(period+", 1 day ago", self.started_on)
      elsif self.nature.quantity?
        if self.product_nature
          period = (self.product_nature.subscription_quantity.blank? ? 1 : self.product_nature.subscription_quantity)||1
        else
          period = 1
        end
        self.first_number ||= self.nature.actual_number
        self.last_number  ||= self.first_number+period-1
      end
    end
  end

  validate do
    if self.address and self.subscriber
      errors.add(:subscriber_id, :entity_must_be_the_same_as_the_contact_entity) if self.address.entity_id != self.subscriber_id
    end
    if self.address
      errors.add(:address_id, :invalid) unless self.address.mail?
    end
  end


  def subscriber_name
    return self.address.mail_line_1
  end

  # Initialize default preferences
  def compute_period
    #self.clean
    if self.product_nature
      self.nature_id ||= self.product_nature.subscription_nature_id
    end
    self.valid? if self.new_record?
    self
  end

  def start
    if self.nature.quantity?
      self.first_number
    elsif self.nature.period?
      if self.started_on.nil?
        ''
      else
        ::I18n.localize(self.started_on)
      end
    end
  end

  def finish
    if self.nature.quantity?
      self.last_number
    elsif self.nature.period?
      if self.stopped_on.nil?
        ''
      else
        ::I18n.localize(self.stopped_on)
      end
    end
  end

  def active?(instant = nil)
    if self.nature.quantity?
      instant ||= self.nature.actual_number
      self.first_number <= instant and instant <= self.last_number
    elsif self.nature.period?
      instant ||= Date.today
      self.started_on <= instant and instant <= self.stopped_on
    end
  end


end
