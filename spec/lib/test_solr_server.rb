# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# A singleton class for starting/stopping a Solr server for testing purposes
# The behavior of TestSolrServer can be modified prior to start() by changing 
# port, solr_home, and quiet properties.

class TestSolrServer
  require 'singleton'
  include Singleton
  attr_accessor :port, :jetty_home, :solr_home, :quiet

  # configure the singleton with some defaults
  def initialize
    @pid = nil
  end

  # Configures the singleton instance of the runner with parameters.
  # Certain defaults are provided for some values. 
  def self.config(params)
    # defaults
    params = {:quiet => true, :jetty_port => 8888}.merge(params)
    self.instance.quiet = params[:quiet]
    self.instance.jetty_home = params[:jetty_home]
    self.instance.solr_home = params[:solr_home]
    self.instance.port = params[:jetty_port]
  end

  def self.wrap(params = {})
    error = false
    self.config(params)
    solr_server = self.instance
    begin
      puts "starting solr server on #{RUBY_PLATFORM}"
      solr_server.start
      sleep params[:startup_wait] || 5
      yield
    rescue
      error = $!
    ensure
      puts "stopping solr server"
      solr_server.stop
    end

    return error
  end
  
  def jetty_command
    "java -Djetty.port=#{@port} -Dsolr.solr.home=#{@solr_home} -jar start.jar"
  end

  # Look up from pid file if possible
  def pid
    unless @pid
      @pid = lookup_pid
    end
    @pid
  end
  
  def start
    puts "jetty_home: #{@jetty_home}"
    puts "solr_home: #{@solr_home}"
    puts "jetty_command: #{jetty_command}"
    platform_specific_start
    write_pid
  end
  
  def stop
    platform_specific_stop
  end  
  
  if RUBY_PLATFORM =~ /mswin32/
    require 'win32/process'

    # start the solr server
    def platform_specific_start
      Dir.chdir(@jetty_home) do
        @pid = Process.create(
              :app_name         => jetty_command,
              :creation_flags   => Process::DETACHED_PROCESS,
              :process_inherit  => false,
              :thread_inherit   => true,
              :cwd              => "#{@jetty_home}"
           ).process_id
      end
      Process.detach(@pid)
    end

    # stop a running solr server
    def platform_specific_stop
      Process.kill(1, pid)
    end
  else # Not Windows
    
    def jruby_raise_error?
      raise 'JRuby requires that you start solr manually, then run "rake spec" or "rake features"' if defined?(JRUBY_VERSION)
    end
    
    # start the solr server
    def platform_specific_start
      
      jruby_raise_error?
      
      puts self.inspect
      Dir.chdir(@jetty_home) do
        @pid = fork do
          STDERR.close if @quiet
          exec jetty_command
        end
      end
      Process.detach(@pid)
    end

    # stop a running solr server
    def platform_specific_stop
      jruby_raise_error?
      Process.kill('TERM', pid)
    end
  end

  protected
  def pid_file_path
    RAILS_ROOT + "/tmp/pids/test_solr.pid"
  end

  # Writes @pid to pid_file_path
  def write_pid
    pid_file = File.open(pid_file_path, "w")
    pid_file.puts @pid
    pid_file.close
  end

  # returns pid found in pid_file_path. Deletes file at pid_file_path.
  # Does not set @pid.
  def lookup_pid
    if File.exists?(pid_file_path)
      pid_file = File.open(pid_file_path, "r")
      pid = pid_file.gets.chomp.to_i
      pid_file.close
      
      File.delete(pid_file_path)
      
      pid
    end
  end
  
end
# 
# puts "hello"
# SOLR_PARAMS = {
#   :quiet => ENV['SOLR_CONSOLE'] ? false : true,
#   :jetty_home => ENV['SOLR_JETTY_HOME'] || File.expand_path('../../jetty'),
#   :jetty_port => ENV['SOLR_JETTY_PORT'] || 8888,
#   :solr_home => ENV['SOLR_HOME'] || File.expand_path('test')
# }
# 
# # wrap functional tests with a test-specific Solr server
# got_error = TestSolrServer.wrap(SOLR_PARAMS) do
#   puts `ps aux | grep start.jar` 
# end
# 
# raise "test failures" if got_error
# 