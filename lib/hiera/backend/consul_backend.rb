# Hiera backend for Consul
class Hiera
  module Backend
    class Consul_backend

      def initialize()
        require 'net/http'
        require 'net/https'
        require 'json'
        @config = Config[:consul]
        if (@config[:host] && @config[:port])
          @consul = Net::HTTP.new(@config[:host], @config[:port])
        else
          raise "[hiera-consul]: Missing minimum configuration, please check hiera.yaml"
        end

        @consul.read_timeout = @config[:http_read_timeout] || 10
        @consul.open_timeout = @config[:http_connect_timeout] || 10
        @cache = {}

        if @config[:use_ssl]
          @consul.use_ssl = true

          if @config[:ssl_verify] == false
            @consul.verify_mode = OpenSSL::SSL::VERIFY_NONE
          else
            @consul.verify_mode = OpenSSL::SSL::VERIFY_PEER
          end

          if @config[:ssl_cert]
            store = OpenSSL::X509::Store.new
            store.add_cert(OpenSSL::X509::Certificate.new(File.read(@config[:ssl_ca_cert])))
            @consul.cert_store = store

            @consul.key = OpenSSL::PKey::RSA.new(File.read(@config[:ssl_key]))
            @consul.cert = OpenSSL::X509::Certificate.new(File.read(@config[:ssl_cert]))
          end
        else
          @consul.use_ssl = false
        end
        build_cache!
      end

      def lookup(key, scope, order_override, resolution_type)

        if resolution_type == :array
          answer = []
        elsif resolution_type == :hash
          answer = {}
        else
          answer = nil
        end

        paths = @config[:paths].map { |p| Backend.parse_string(p, scope, { 'key' => key }) }
        paths.insert(0, order_override) if order_override

        catch (:found) do
          paths.each do |path|
            Hiera.debug("[hiera-consul]: Checking path #{path}")
            # We only support querying the catalog or the kv store
            if path !~ /^\/v\d\/(catalog|kv)\//
              Hiera.debug("[hiera-consul]: We only support queries to catalog and kv and you asked #{path}, skipping")
              next
            end
            # Check that we are not looking somewhere that will make hiera crash subsequent lookups
            if "#{path}".match("//")
              Hiera.debug("[hiera-consul]: The specified path #{path}/#{key_delimited} is malformed, skipping")
              next
            end
            if path == 'services'
              if @cache.has_key?(key)
                answer = @cache[key]
                return answer
              end
            end
  

  #lookup fully qualified path
            [key, key.gsub('::', '/')].each do | key_delimited | 
              this_answer = wrapquery("#{path}/#{key_delimited}")
              if resolution_type == :array
                answer = answer + this_answer unless ! this_answer
              elsif resolution_type == :hash
                answer = this_answer.merge(answer) unless ! this_answer #Earliest value takes precedence
              else #if resolution_type == :priority
                answer = this_answer 
                throw :found if answer
              end
            end

  #lookup partial path plus yaml/json
            [key, key.gsub('::', '/')].each do | key_delimited | 
              key_parts=key_delimited.split("/")
              Hiera.debug("[hiera-consul]: key_delimited is now #{key_delimited}")
              Hiera.debug("[hiera-consul]: key_parts is now #{key_parts}")
              # search most specific first
              hash_key_parts=[]
              while key_parts.size>0 do
                hash_key_parts = hash_key_parts + [key_parts.pop]
                key_reconstructed=key_parts.join('/')
                this_answer = wrapquery("#{path}/#{key_reconstructed}")
                hash_key_parts_copy = hash_key_parts
                while this_answer.is_a? Hash do
                  this_answer=this_answer[hash_key_parts_copy[0]]
                  hash_key_parts_copy.shift
                end
                next if this_answer.nil?
                if resolution_type == :array
                  answer = answer + this_answer unless ! this_answer
                elsif resolution_type == :hash
                  answer = this_answer.merge(answer) unless ! this_answer #Earliest value takes precedence
                else #if resolution_type == :priority
                  answer = this_answer 
                  throw :found if answer
                end
              end
            end

  #lookup base path plus yaml/json
            [key, key.gsub('::', '/')].each do | key_delimited | 
              hash_key_parts=key_delimited.split("/")
              this_answer = wrapquery("#{path}")
              while this_answer.is_a? Hash do
                this_answer=this_answer[hash_key_parts[0]]
                hash_key_parts.shift
              end
              next if this_answer.nil?
              if resolution_type == :array
                answer = answer + this_answer unless ! this_answer
              elsif resolution_type == :hash
                answer = this_answer.merge(answer) unless ! this_answer #Earliest value takes precedence
              else #if resolution_type == :priority
                answer = this_answer 
                throw :found if answer
              end
            end

            Hiera.debug("[hiera-consul]: Answer is now #{answer}")
          end
        end
        answer
      end

      def parse_result(res)
          require 'base64'
          answer = nil
          if res == "null"
            Hiera.debug("[hiera-consul]: Jumped as consul null is not valid")
            return answer
          end
          # Consul always returns an array
          res_array = JSON.parse(res)
          # See if we are a k/v return or a catalog return
          if res_array.length > 0
            if res_array.first.include? 'Value' 
              if res_array.first['Value'].nil?
                answer=nil
              else
                answer = Base64.decode64(res_array.first['Value'])
              end
            else
              answer = res_array
            end
          else
            Hiera.debug("[hiera-consul]: Jumped as array empty")
          end
          return answer
      end

      private

      def token(path)
        # Token is passed only when querying kv store
        if @config[:token] and path =~ /^\/v\d\/kv\//
          return "?token=#{@config[:token]}"
        else
          return nil
        end
      end

      def wrapquery(path)

          Hiera.debug("[hiera-consul]: Lookup #{path} on #{@config[:host]}:#{@config[:port]}")

          httpreq = Net::HTTP::Get.new("#{path}#{token(path)}")
          answer = nil
          begin
            result = @consul.request(httpreq)
          rescue Exception => e
            Hiera.debug("[hiera-consul]: Could not connect to Consul")
            raise Exception, e.message unless @config[:failure] == 'graceful'
            return answer
          end
          unless result.kind_of?(Net::HTTPSuccess)
            Hiera.debug("[hiera-consul]: HTTP response code was #{result.code}")
            return answer
          end
          answer = parse_result(result.body)
          Hiera.debug("[hiera-consul]: Answer from #{path} was #{answer}")
          success=false
          if @config[:autoconvert]
              if @config[:autoconvert].include? 'yaml'
                  require 'yaml'
                  begin
                      answer = YAML.load(answer)
                      Hiera.debug("[hiera-consul]: Answer was autoconverted as yaml")
                      success=true
                  rescue
                      Hiera.debug("[hiera-consul]: Answer was NOT autoconverted as yaml")
                  end
              end
              if @config[:autoconvert].include? 'json' and ! success
                  require 'json'
                  begin
                      answer = JSON.load(answer)
                      Hiera.debug("[hiera-consul]: Answer was autoconverted as json")
                      success=true
                  rescue
                      Hiera.debug("[hiera-consul]: Answer was NOT autoconverted as json")
                  end
              end
          end
          return answer
      end

      def build_cache!
          services = wrapquery('/v1/catalog/services')
          return nil unless services.is_a? Hash
          services.each do |key, value|
            service = wrapquery("/v1/catalog/service/#{key}")
            next unless service.is_a? Array
            service.each do |node_hash|
              node = node_hash['Node']
              node_hash.each do |property, value|
                # Value of a particular node
                next if property == 'ServiceID'
                unless property == 'Node'
                  @cache["#{key}_#{property}_#{node}"] = value
                end
                unless @cache.has_key?("#{key}_#{property}")
                  # Value of the first registered node
                  @cache["#{key}_#{property}"] = value
                  # Values of all nodes
                  @cache["#{key}_#{property}_array"] = [value]
                else
                  @cache["#{key}_#{property}_array"].push(value)
                end
              end
            end
          end
          Hiera.debug("[hiera-consul]: Cache #{@cache}")
      end

    end
  end
end
