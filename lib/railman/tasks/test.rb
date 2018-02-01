s = File.read(File.join(File.dirname(__FILE__), 'nginx.conf'))
s.gsub!('DOMAINS', 'faluninfo.ba www.faluninfo.ba')
s.gsub!('APPLICATION', 'faluninfo')
puts s