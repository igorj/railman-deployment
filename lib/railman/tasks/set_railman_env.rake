task :set_railman_env do
  set :deploy_to, "/home/deploy/apps/#{fetch(:application)}"
  set :environment, { rails_env: 'production'}
  set :chruby_prefix, "/usr/local/bin/chruby-exec #{fetch(:chruby_ruby)} -- RAILS_ENV=production "

  SSHKit.config.command_map[:rake] = "#{fetch(:chruby_prefix)} DISABLE_DATABASE_ENVIRONMENT_CHECK=1 #{fetch(:deploy_to)}/bin/rake"
  SSHKit.config.command_map[:bundle] = "#{fetch(:chruby_prefix)} #{fetch(:deploy_to)}/bin/bundle"
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
before :remove, :set_railman_env
