Spree::Order.class_eval do
  attr_accessor :store_credit_amount

  def store_credit_amount
    adjustments.store_credits.sum(:amount).abs.to_f
  end

  # in case of paypal payment, item_total cannot be 0
  def store_credit_maximum_amount
    item_total - 0.01
  end

  # returns the maximum usable amount of store credits
  def store_credit_maximum_usable_amount
    if user.store_credits_total > 0
      user.store_credits_total > store_credit_maximum_amount ? store_credit_maximum_amount : user.store_credits_total
    else
      0
    end
  end

  def process_store_credit(amount_in_usd)
    if amount_in_usd > 0 && amount_in_usd <= self.store_credit_maximum_usable_amount
      self.adjustments.store_credits.create(
        order_id: self.id, 
        label: Spree.t(:store_credit), 
        amount: - amount_in_usd * Spree::PriceBook.find_by(currency: self.currency).price_adjustment_factor
      )
      self.consume_users_credit
      self.contents.send(:reload_totals)
      true
    else
      false
    end
  end

  def consume_users_credit
    return unless user.present?
    credit_used = self.store_credit_amount / Spree::PriceBook.find_by(currency: self.currency).price_adjustment_factor

    user.store_credits.each do |store_credit|
      break if credit_used == 0
      if store_credit.remaining_amount > 0
        if store_credit.remaining_amount > credit_used
          store_credit.remaining_amount -= credit_used
          store_credit.save
          credit_used = 0
        else
          credit_used -= store_credit.remaining_amount
          store_credit.update_attribute(:remaining_amount, 0)
        end
      end
    end
  end

  def restore_users_credit
    return unless user.present?
    credit_to_restore = self.store_credit_amount / Spree::PriceBook.find_by(currency: self.currency).price_adjustment_factor

    user.store_credits.each do |store_credit|
      break if credit_to_restore == 0
      store_credit_restore_amount = store_credit.amount - store_credit.remaining_amount

      if store_credit_restore_amount > credit_to_restore
        store_credit.remaining_amount += credit_to_restore
        store_credit.save
        credit_to_restore = 0
      else
        credit_to_restore -= store_credit_restore_amount
        store_credit.update_attribute(:remaining_amount, store_credit.amount)
      end
    end
  end

end
