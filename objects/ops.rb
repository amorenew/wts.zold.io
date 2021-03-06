# Copyright (c) 2018-2019 Zerocracy, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'tempfile'
require 'openssl'
require 'zold/log'
require 'zold/age'
require_relative 'user_error'

#
# Operations with a user.
#
class Ops
  def initialize(item, user, wallets, remotes, copies, log: Zold::Log::NULL, network: 'test')
    @user = user
    @item = item
    @wallets = wallets
    @remotes = remotes
    @copies = copies
    @log = log
    @network = network
  end

  def pull
    start = Time.now
    id = @item.id
    raise UserError, "There are no visible remote nodes, can\'t PULL #{id}" if @remotes.all.empty?
    require 'zold/commands/pull'
    begin
      Zold::Pull.new(wallets: @wallets, remotes: @remotes, copies: @copies, log: @log).run(
        ['pull', id.to_s, "--network=#{@network}", '--retry=4', '--shallow']
      )
    rescue Zold::Fetch::NotFound => e
      raise UserError, "We didn't manage to find your wallet in any of visible Zold nodes. \
You should try to PULL again. If it doesn't work, most likely your wallet #{id} is lost \
and can't be recovered. If you have its copy locally, you can push it to the \
network from the console app, using PUSH command. Otherwise, go for \
the RESTART option in the top menu and create a new wallet. We are sorry to \
see this happening! #{e.message}"
    rescue Zold::Fetch::EdgesOnly, Zold::Fetch::NoQuorum => e
      raise UserError, e.message
    end
    @log.info("Wallet #{id} pulled successfully in #{Zold::Age.new(start)}")
  end

  def push
    start = Time.now
    id = @item.id
    raise UserError, "There are no visible remote nodes, can\'t PUSH #{id}" if @remotes.all.empty?
    require 'zold/commands/push'
    begin
      Zold::Push.new(wallets: @wallets, remotes: @remotes, log: @log).run(
        ['push', id.to_s, "--network=#{@network}", '--retry=4']
      )
    rescue Zold::Push::EdgesOnly, Zold::Push::NoQuorum => e
      raise UserError, e.message
    end
    @log.info("Wallet #{id} pushed successfully in #{Zold::Age.new(start)}")
  end

  # Pay all required taxes, no matter what is the amount.
  def pay_taxes(keygap)
    raise "The user @#{@user.login} is not registered yet" unless @item.exists?
    raise "The account @#{@user.login} is not confirmed yet" unless @user.confirmed?
    start = Time.now
    id = @item.id
    pull
    raise 'There is no wallet file after PULL, can\'t pay taxes' unless @wallets.acq(id, &:exists?)
    Tempfile.open do |f|
      File.write(f, @item.key(keygap))
      require 'zold/commands/taxes'
      Zold::Taxes.new(wallets: @wallets, remotes: @remotes, log: @log).run(
        ['taxes', 'pay', "--network=#{@network}", '--private-key=' + f.path, id.to_s]
      )
    end
    push
    @log.info("Taxes paid for #{id} in #{Zold::Age.new(start)}")
  end

  def pay(keygap, bnf, amount, details)
    raise UserError, 'Payment amount can\'t be zero' if amount.zero?
    raise UserError, 'Payment amount can\'t be negative' if amount.negative?
    raise "The user @#{@user.login} is not registered yet" unless @item.exists?
    raise "The account @#{@user.login} is not confirmed yet" unless @user.confirmed?
    start = Time.now
    id = @item.id
    pull
    raise 'There is no wallet file after PULL, can\'t pay' unless @wallets.acq(id, &:exists?)
    Tempfile.open do |f|
      File.write(f, @item.key(keygap))
      require 'zold/commands/pay'
      Zold::Pay.new(wallets: @wallets, remotes: @remotes, copies: @copies, log: @log).run(
        ['pay', "--network=#{@network}", '--private-key=' + f.path, id.to_s, bnf.to_s, "#{amount.to_i}z", details]
      )
    end
    push
    @log.info("Paid #{amount} from #{id} to #{bnf} in #{Zold::Age.new(start)}: #{details}")
  end

  def migrate(keygap)
    start = Time.now
    pay_taxes(keygap)
    origin = @user.item.id
    balance = @user.wallet(&:balance)
    target = Tempfile.open do |f|
      File.write(f, @user.wallet(&:key).to_s)
      require 'zold/commands/create'
      Zold::Create.new(wallets: @wallets, log: @log).run(
        ['create', '--public-key=' + f.path]
      )
    end
    pay(keygap, target, balance, 'Migrated')
    @user.item.replace_id(target)
    push
    @log.info("Wallet of @#{@user.login} migrated from #{origin} to #{target} \
with #{balance}, in #{Zold::Age.new(start)}")
  end
end
