module Vagrant
  module Provisioners
    # This class implements provisioning via chef-client, allowing provisioning
    # with a chef server.
    class ChefServer < Chef
      def prepare
        if Vagrant.config.chef.validation_key_path.nil?
          raise Actions::ActionException.new(<<-msg)
Chef server provisioning requires that the `config.chef.validation_key_path` configuration
be set to a path on your local machine of the validation key used to register the
VM with the chef server.
msg
        end

        if Vagrant.config.chef.chef_server_url.nil?
          raise Actions::ActionException.new(<<-msg)
Chef server provisioning requires that the `config.chef.chef_server_url` be set to the
URL of your chef server. Examples include "http://12.12.12.12:4000" and
"http://myserver.com:4000" (the port of course can be different, but 4000 is the default)
msg
        end
      end

      def provision!
        chown_provisioning_folder
        upload_validation_key
        setup_json
        setup_config
        run_chef_client
      end

      def upload_validation_key
        logger.info "Uploading chef client validation key..."
        SSH.upload!(Vagrant.config.chef.validation_key_path, guest_validation_key_path)
      end

      def setup_config
        solo_file = <<-solo
log_level          :info
log_location       STDOUT
ssl_verify_mode    :verify_none
chef_server_url    "#{Vagrant.config.chef.chef_server_url}"

validation_client_name "#{Vagrant.config.chef.validation_client_name}"
validation_key         "#{guest_validation_key_path}"
client_key             "/etc/chef/client.pem"

file_store_path    "/srv/chef/file_store"
file_cache_path    "/srv/chef/cache"

pid_file           "/var/run/chef/chef-client.pid"

Mixlib::Log::Formatter.show_time = true
solo

        logger.info "Uploading chef-client configuration script..."
        SSH.upload!(StringIO.new(solo_file), File.join(Vagrant.config.chef.provisioning_path, "client.rb"))
      end

      def run_chef_client
        logger.info "Running chef-client..."
        SSH.execute do |ssh|
          ssh.exec!("cd #{Vagrant.config.chef.provisioning_path} && sudo chef-client -c client.rb -j dna.json") do |channel, data, stream|
            # TODO: Very verbose. It would be easier to save the data and only show it during
            # an error, or when verbosity level is set high
            logger.info("#{stream}: #{data}")
          end
        end
      end

      def guest_validation_key_path
        File.join(Vagrant.config.chef.provisioning_path, "validation.pem")
      end
    end
  end
end