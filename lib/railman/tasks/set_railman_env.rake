task :set_railman_env do
  set :deploy_to, "/home/deploy/apps/#{fetch(:application)}"
  if fetch(:spa_application)
    set :deploy_spa_to, "/home/deploy/sites/#{fetch(:spa_application)}"
  end
  set :rbenv_home, '/home/deploy/.rbenv'
  set :environment, {path: "#{fetch(:rbenv_home)}/shims:#{fetch(:rbenv_home)}/bin:$PATH", rails_env: 'production'}

  SSHKit.config.command_map[:rake] = "#{fetch(:deploy_to)}/bin/rake"
  %w(ln cp service start restart stop status certbot).each do |cmd|
    SSHKit.config.command_map[cmd.to_sym] = "sudo #{cmd}"
  end
  SSHKit.config.command_map[:eye] = "#{fetch(:rbenv_home)}/shims/eye"
  SSHKit.config.command_map[:su_rm] = 'sudo rm'
end

before :setup, :set_railman_env
before :deploy, :set_railman_env
before :deploy_spa, :set_railman_env
before :deploy_all, :set_railman_env
before :update, :set_railman_env
before :reset_server, :set_railman_env
before :remove, :set_railman_env
