# Copyright (c) 2018 Yegor Bugayenko
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

require 'zold/log'
require 'coinbase/wallet'
require_relative 'user_error'

#
# BTC sending out gateway (via Coinbase).
#
class Bank
  # Fake gateway
  class Fake
    def send(_address, _usd, _description)
      # nothing
    end
  end

  def initialize(key, secret, account, log: Zold::Log::NULL)
    @key = key
    @secret = secret
    @account = account
    @log = log
  end

  # Send BTC
  def send(address, usd, description)
    acc = Coinbase::Wallet::Client.new(api_key: @key, api_secret: @secret).account(@account)
    acc.send(to: address, amount: usd, currency: 'USD', description: description)
  end
end
