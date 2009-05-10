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
          receive_file(params)
        elsif params['destroy']
          destroy_file(params)
        else
          send_file(params)
        end
      else
        [@status, @headers, @body]
      end
    end

    private

    # some file sending/receiving code adapted from Rack::File

    def destroy_file
      with_sanitized_path(params['path']) do |sanitized_path|        
        with_modifiable_path(sanitized_path) do |dest_path|
          
        end
      end
    end
    
    def receive_file(params)
      with_sanitized_path(params['path']) do |sanitized_path|        
        with_modifiable_path(sanitized_path) do |dest_path|
          write_to_file(params,dest_path)
        end
      end
    rescue StandardError
      return forbidden("Cannot save '#{params['path']}' due to #{$!.message}")
    end
  
    def write_to_file(params,dest_path)
      # if they sent us a file, then we do something with it, otherwise it was just a touch
      if params['file'][:tempfile]
        source_path = params['file'][:tempfile].path

        if params['append']
          File.open(dest_path,'a') do |dest_file|
            File.open(source_path,'r') do |source_file|
              FileUtils.copy_stream(source_file,dest_file)
            end
          end
        else
          FileUtils.mv(source_path,dest_path)
          msg = "Saved #{dest_path}"
        end
      end

      [ 200, { 'Content-Type' => 'text/html' }, "Saved #{dest_path}" ]
    end
    
    def send_file(params)
      with_sanitized_path(params['path']) do |sanitized_path|
        with_readable_path(sanitized_path) do |path|
          send_file_response(path)
        end
      end
    rescue StandardError
      return forbidden("Cannot send '#{params['path']}' due to #{$!.message}")
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

    def with_readable_path(path)
      return not_found(path) unless ::File.file?(path)
      return forbidden("Cannot read #{path}") unless ::File.readable?(path)      
      yield path
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
        
    def with_modifiable_path(path)      
      # can't use File.dirname here as it only uses Unix separator
      path_parts = path.split(File::SEPARATOR)
      dir_name = path_parts.join(a[0..-2])
      File.mkdir_p(dir_name)
      # TODO STILL DO A WRITE CHECK HERE!!
      FileUtils.touch(path)
      yield path
    rescue Errno::EACCES
      return forbidden("Cannot write to #{path} due to #{$!.message}")
    end

  end
end

if $0 == __FILE__
  require 'rack/showexceptions'
  app = lambda { [200,{ 'Content-Type' => 'text/plain' },''] }
  Rack::Handler::WEBrick.run(Rack::ShowExceptions.new(Rack::Lint.new(Rack::Repository.new(app))),:Port => 3000)
end