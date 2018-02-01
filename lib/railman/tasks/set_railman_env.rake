task :set_railman_env do
  set :deploy_to, "/home/deploy/apps/#{fetch(:application)}"
  set :environment, {path: "#{fetch(:rbenv_home)}/shims:#{fetch(:rbenv_home)}/bin:$PATH", rails_env: 'production'}  # todo ???

  SSHKit.config.command_map[:rake] = "#{fetch(:deploy_to)}/bin/rake"
  %w(systemctl certbot).each do |cmd|
    SSHKit.config.command_map[cmd.to_sym] = "sudo #{cmd}"
  end
  SSHKit.config.command_map[:su_rm] = 'sudo rm'
  SSHKit.config.command_map[:su_ln] = 'sudo ln'
  SSHKit.config.command_map[:su_cp] = 'sudo cp'
end

before :setup, :set_railman_env
before :deploy, :set_railman_env
before :update, :set_railman_env
before :reset_server, :set_railman_env
before :remove, :set_railman_env
