begin
  require 'spec'
rescue LoadError
  require 'rubygems'
  gem 'rspec'
  require 'spec'
end

$:.unshift(File.dirname(__FILE__) + '/../lib')
require 'repository'

context "Rack::Repository" do
  
  def new_request
    Rack::MockRequest.new(Rack::Repository.new)
  end

  def stub_readable_file(path,mtime)
    File.stub!(:file?).and_return(true)
    File.stub!(:readable?).and_return(true)
    File.stub!(:size?).and_return(500)
    File.stub!(:mtime).and_return(mtime)
    @rack_file = stub('rack_file').as_null_object
    Rack::File::stub!(:new).and_return(@rack_file)
  end
  
  specify "initializes" do
    lambda { Rack::Repository.new }.should_not raise_error
  end

  context "basic request handling" do
    specify "returns forbidden when called with an empty action" do
      new_request.get("/fancy/file.txt?action=").should be_forbidden
    end

    specify "returns forbidden when called with an unknown action" do
      new_request.get("/fancy/file.txt?action=craziness").should be_forbidden
    end
  end
  
  context "sending files to client" do

    # illegal path
    # root dir
    # ::File.file?(path)
    # ::File.readable?(path)
    # ::File.size?(path)
    #       [200, {
      #   "Last-Modified"  => ::File.mtime(path).httpdate,
      #   "Content-Type"   => Mime.mime_type(::File.extname(path), 'text/plain'),
      #   "Content-Length" => size.to_s
      # }, body]

    before(:each) do
      @requested_path ||= "/i/want/this/file.txt"
      @mtime ||= Time.utc(2009,5,12,17,22)
      stub_readable_file(@requested_path,@mtime)
    end
    
    
    specify "is successful" do
      new_request.get(@requested_path).should be_ok
    end
    
  end
  
end