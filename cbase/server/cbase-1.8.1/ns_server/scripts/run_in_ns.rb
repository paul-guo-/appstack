#!/usr/bin/env ruby

puts "my argv:"
puts ARGV.join(' ')

require 'socket'

def sh(*args)
  print "# #{args.join(' ')}\n"
  unless system(*args)
    raise "failed"
  end
end

def poll_for_condition(timeout=10.0, delay=0.1, &block)
  deadline = Time.now + timeout
  return if yield
  begin
    sleep delay
    return if yield
  end while (Time.now < deadline)
  raise "timed out"
end

if ARGV == ["--setup"]
  puts "will set things up for host (assuming 172.25.0/24 subnetwork for 'cluster')"
  puts "spawning host's vde switch"
  sh "mkdir -p /tmp/vdesock"
  sh "vde_switch -s /tmp/vdesock/c_main -t tapMain -d"
  puts "setting up host's tap interface"
  sh "ifconfig tapMain 172.25.0.1/24 up"
  puts "done."
  exit
end

# apparently vde is eating HUP. Or maybe not. Anyway ruby is normally
# messing up with SIGHUP, so lets make it at least do some work for
# us. That sending out of SIGTERM is really crucial here
trap("HUP") do
  # puts "broadcasting TERM"
  trap("TERM") {exit}
  Process.kill("TERM", 0)
  exit
end

sleeper = fork do
  # NOTE: we'll inherit SIGHUP action. This sleeper process is
  # normally the guy to handle killing rest of our pgroup
  #
  # this process ensures that we have stopped process in our process
  # group.
  #
  # This will cause whole group to be sent SIGHUP when process group
  # will become orphaned. That will happen when our main process or
  # it's parent will die.
  while true
    sleep 3600
  end
end
Process.kill("STOP", sleeper)

dummy_name, node_name = ARGV.each_cons(2).detect {|(maybe_name, val)| maybe_name == "-name"}

raise unless node_name =~ /\Ans?_([0-9]+)@/

node_number = $1.to_i
node_host = $'

vde_sock = "/tmp/vdesock/c_node_#{node_number}"
tap_if = "tapCNode#{node_number}"
netns = "c_node_#{node_number}"
ifaddr = "172.25.0.#{2+node_number}"

puts "Creating vde switch"
sh "vde_switch -s #{vde_sock} -t #{tap_if} &"
puts "Wiring it to host side"
rd, wr = IO.pipe
# wirefilter a) seems to mess terminal settings a bit thus we protect
# real stdout via pipe to cat and b) seems to expect some "console"
# commands on stdin. Which we fake with empty pipe
sh "wirefilter -v #{vde_sock}:/tmp/vdesock/c_main -d 1 -s 30M 0<&#{rd.fileno}- #{wr.fileno}<&- 2>&1 | cat &"
rd.close
# we keep write side for extra safety. I.e. we could leave it open in
# child process. But we close it in child and keep it open in
# ourselves (in fact it'll be open in erlang and all it's child :). So
# when we're 'done' wirefilter has less chance 'escaping'
puts "Creating netns"
sh "ip netns del #{netns}; ip netns add #{netns}"
sh "ip netns exec #{netns} ifconfig lo 127.0.0.1/8 up"
puts "Passing tap interface into netns"
sh "ip link set #{tap_if} netns #{netns}"
puts "Setting up tap interface"
sh "ip netns exec #{netns} ifconfig #{tap_if} #{ifaddr}/24 up"
puts "cleaning up arp entry for child ifaddr (because of different mac address of new tap interface)"
sh "arp -d #{ifaddr} || true"

# we need to replace hostname in args because original ip is not part
# of new netns.
new_args = ARGV.map do |arg|
  if arg == node_name
    "n_#{node_number}@#{ifaddr}"
  else
    arg
  end
end

# erlang would spawn epmd for us normally. But it would daemonize
# itself. Which we don't need. We want it to receive HUP & TERM
# signals so that there's nobody running in our netns after we're done
puts "spawning epmd in our pgroup"
# sh "ip netns exec #{netns} erl -noshell -setcookie nocookie -sname init -run init stop 2>&1 > /dev/null"
sh "ip netns exec #{netns} epmd </dev/null >/dev/null 2>&1 &"

poll_for_condition do
  begin
    puts "checking epmd alivedness"
    TCPSocket.new(ifaddr, 4369).close
    true
  rescue Errno::ECONNREFUSED
    false
  end
end

puts "exec-ing erlang #{new_args.join(' ')}"
STDOUT.flush
STDERR.flush
exec("ip", "netns", "exec", netns, *new_args)
raise "cannot happen"
