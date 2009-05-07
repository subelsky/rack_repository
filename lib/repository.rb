# OPTIMIZE if the IDE server is x-sendfile aware, we can use Rack::Sendfile to speed up sending a message 

require 'rubygems'
require 'rack'
require 'rack/request'
require 'rack/utils'
require 'rack/file'

module Rack
  class Repository
    
    def initialize(app,root_dir = nil)
      @app = app
      @root_dir ||= ::File.expand_path(::File.dirname(__FILE__))
    end

    def call(env)
      @status, @headers, @body = @app.call(env)
      params = Request.new(env).params
            
      if params['path']
        if params['file']
          receive_file(params,env)
        else
          send_file(params,env)
        end
      else
        [@status, @headers, @body]
      end
    end

    private

    # some file sending/receiving code adapted from Rack::File

    def receive_file(params,env)
      with_sanitized_path(params['path']) do |path|
        return forbidden("#{path} does not exist") unless ::File.exist?(path)
        return forbidden("Cannot write to #{path}") unless ::File.writable?(path)

        source_path = params['file'][:tempfile].path
        destination_filename = ::File.basename(Utils.unescape(params['file'][:filename]))
        destination_path = ::File.join(path, destination_filename)
      
        FileUtils.mv(source_path,destination_path)
        [ 200, { 'Content-Type' => 'text/html' }, "Saved #{destination_path}" ]
      end
    end
  
    def send_file(params,env)
      with_sanitized_path(params['path']) do |path|
        return not_found(path) unless ::File.file?(path)
        return forbidden("Cannot read #{path}") unless ::File.readable?(path)
        send_file_response(path)
      end
    end

    def send_file_response(path)
      if size = ::File.size?(path)
        # use Rack::File so streaming works and for max compatibility with other handlers
        # OPTIMIZE we could make this work with Rack::Sendfile pretty easily if the server supports it
        body = Rack::File::new(@root_dir)
        body.path = path
        body
      else
        # file does not provide size info via stat, so we have to read it into memory
        body = [::File.read(path)]
        size = Utils.bytesize(body.first)
      end

      [200, {
        "Last-Modified"  => ::File.mtime(path).httpdate,
        "Content-Type"   => Mime.mime_type(::File.extname(path), 'text/plain'),
        "Content-Length" => size.to_s
      }, body]
    end

    def with_sanitized_path(orig_path)
      path = Utils.unescape(orig_path)
      return forbidden("Illegal path #{path}") if path.include?("..")

      yield ::File.join(@root_dir, path)
    end

    def not_found(path)
      body = "File not found: #{path}\n"
      [404, {"Content-Type" => "text/plain", "Content-Length" => body.size.to_s},[body] ]
    end
    
    def forbidden(body)
      body += "\n" unless body =~ /\n$/
      [403, {"Content-Type" => "text/plain", "Content-Length" => body.size.to_s},[body]]
    end

  end
end

if $0 == __FILE__
  require 'rack/showexceptions'
  app = lambda { [200,{ 'Content-Type' => 'text/plain' },''] }
  Rack::Handler::WEBrick.run(Rack::ShowExceptions.new(Rack::Lint.new(Rack::Repository.new(app))),:Port => 3000)
end