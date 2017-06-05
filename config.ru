require 'thread'
require 'securerandom'
require 'json'

class App

  class Client
    attr_accessor :seq, :last_rotated, :id
  end

  def initialize
    @mutex = Mutex.new
    @clients = {}
  end

  def call(env)

    request = Rack::Request.new(env)

    req_client_id = request.cookies["client_id"]
    req_client_seq = 0

    client = nil

    if req_client_id
      @mutex.synchronize do
        if client = @clients[req_client_id]
          req_client_seq = request.cookies["client_seq"].to_i
        else
          req_client_id = nil
        end
      end
    end

    bumped = false
    error = nil
    if req_client_id && client
      @mutex.synchronize do
        if client.seq == req_client_seq
          if (Time.now - client.last_rotated) > 3
            client.last_rotated = Time.now
            client.seq = client.seq + 1
            bumped = true
          end
        elsif client.seq-1 == req_client_seq
          # old req, so skip, but also set cookie
          bumped = true
        else
          error = "Unexpected seq #{req_client_seq} was expecting #{client.seq}"
        end
      end
    end

    json = {
      error: error,
      seq: client&.seq
    }.to_json

    html = <<HTML
    <html>
      <body>
        <p>
          Client ID: #{req_client_id} <br>
          Client Seq: <span id='seq'>#{req_client_seq}</span>
        </p>
        <p id='error'>
          #{error}
        </p>

        <script>
          var doReq = function() {
            var ajax = new XMLHttpRequest();
            ajax.open('GET', '/', true);
            ajax.setRequestHeader('Req-Ajax', 'true');
            ajax.onreadystatechange = function() {
              if (ajax.readyState === 4) {
                var json = JSON.parse(ajax.responseText);
                if (json.error) {
                  elem = document.getElementById('error');
                  elem.innerHTML = (elem.innerHTML || '') + "<br>" + json.error;
                }
                if (json.seq) {
                  elem = document.getElementById('seq');
                  elem.innerHTML = json.seq;
                }
              }
            }
            ajax.send();
          };

          var doReqs = function() {
            doReq();
            doReq();
            doReq();
          };

          setInterval(doReqs, 1000);
        </script>
      </body>
    </html>
HTML

    response =
      if env['HTTP_REQ_AJAX']
        Rack::Response.new json, 200, {'Content-Type' => 'application/json'}
      else
        Rack::Response.new html, 200, {}
      end

    if !req_client_id
      client = Client.new
      client.id = SecureRandom.hex
      client.seq = 0
      client.last_rotated = Time.now
      @clients[client.id] = client
      response.set_cookie("client_id", {value: client.id, path: '/', expires: Time.now+24*60*60, httponly: true})
      response.set_cookie("client_seq", {value: client.seq, path: '/', expires: Time.now+24*60*60, httponly: true})
    end

    if bumped
      response.set_cookie("client_seq", {value: client.seq, path: '/', expires: Time.now+24*60*60, httponly: true})
    end

    response.finish
  end
end


map '/' do
  run App.new
end
