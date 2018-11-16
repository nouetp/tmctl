#!/usr/bin/env ruby
#
#	class to manage tmux
#
require 'yaml'

class TmuxCTL

  attr_accessor :user,:data_dir,:debug_level,:default_layout,:sessions,:tm_name,:logfile

  def initialize(session=:new,data_dir="data/")
	@tm_name=(session==:new or session.nil? or session.empty?) ? "tmux-ctl" : session
	@session=session
	@logfile="log/tmuxctl.log"
	@sessions={}
	@data_dir=data_dir
	@synced=false
	@debug_level=51
	@default_layout="tiled"
	@managed=[]
	get_sessions
	puts new_session(@tm_name) if ! @sessions.keys.include? @tm_name
  end

	#	Debugging info: 

  def dputs(str,level=1)
	format="%20s %-100s \n"
	if level<=@debug_level
		str.each_line do |line|
			printf(format,"[debug(#{level})]> ",line.chomp) 
			log sprintf(format,"[debug(#{level})]> ",line.chomp) 
			end
		end
  end


	#	Option config:

  def window_selection(option=:new,win=0)
	return @win_sel if @win_sel
	@win_sel=:new
	@win_sel=option if [:new,:replace,:all].include? option
	@window=(@win_sel==:replace) ? win : nil
	@win_sel
  end

  def hosts (hosts=[])
	@hosts=(hosts.class==Array) ? hosts : hosts.split(',')
  end


	#	tmux session reference:

  def win(w=0)
	@session+":"+w.to_s
  end

  def pane(w=0,p=0)
	win(w.to_s)+"."+p.to_s
  end

	#	profile loading/saving:

  def load_profile(profile)
	y=File.read(profile+".yml",'r')
	r=YAML.load(y)
  end

  def save_profile(profile,data)
	f=File.open(profile+".yml","w")
	f.puts YAML.dump(data)
	f.close
  end

  def log(message)
	f=File.open(@logfile,'a')
	f.puts message
	f.close
  end

	#	Command execution:

  def command(cmd,args=[],session=@session)
	dputs "cmd: '#{cmd}', args: '#{args.inspect}', session: '#{session.inspect}'",50
	sess_arg=""
	sess_arg="-t #{session}" if !session.nil? and ! cmd.include? " -s "
	com="tmux -v #{cmd} #{sess_arg} #{args.join(' ')}"
	dputs "#{com}",10
	r=`#{com}`
	ec=$?
	dputs "#{r}",50
	dputs "exit-code: #{ec}" if @debug_level>20 
	raise "command '#{com}'('#{cmd}') errored !" if ec!=0 and @debug_level>50 and cmd!="list-sessions 2>&1"
	r
  end

	# Threaded version to call commands in threads
  def tcommand(cmd,args=[],session=@session)
	t=Thread.new(cmd,args,session) do |c,a,s|
		command(c,a,s)
		end
  end

  def pane_cmd(cmd,w=0,p=0)
	cmd=[cmd] if cmd.class=String
	cmd<<"ENTER" if cmd.last!="ENTER"
	command("send",cmd,pane(p,w))
  end

  def cmd_allpanes(cmd=[],win=0)
	cmd=[cmd] if cmd.class==String
	s=@synced
	psync if !@synced
	cmd.each do |c|
		pane_cmd(c,0,win)
		end
	psync if s!=@synced
  end

  def managed?(win=:any,pane=:any)
	man=false
	return man if @managed.empty?
	@managed.each do |h|
		man=true if (h[:window]==win or win==:any) and (h[:pane]==pane or pane==:any)
		end
	man
  end

	#	pass block to matching windows/panes:

  def command_panes(windows=:managed,panes=:managed,&block)
	@sessions[@session][:windows].keys.each do |win|
		next if windows!=:all and windows.class==Regexp and !win.to_s.match windows
		next if windows!=:all and windows.class==String and !win.to_s.include? windows
		next if windows!=:all and windows.class==Fixnum and win.to_i!=windows
		next if windows==:managed and !managed(win,:any)
		@session[@session][:windows][win][:panes].keys.each do |pain|
			next if panes!=:all and panes.class==Regexp and !pain.to_s.match panes
			next if panes!=:all and panes.class==String and !pain.to_s.include? panes
			next if panes!=:all and panes.class==Fixnum and pain.to_i!=panes
			next if panes==:managed and !managed(win,pane)
			block.call(win,pain)
			end
		end
  end

  def new_session(name=@tm_name)
	puts "NEW SESSION CALLED"
	ns=tcommand("new -s #{name}")
	ns=tcommand("attach", [],name)
	get_sessions
  end
	#	Session collection:

  def get_sessions
	sess_rx=/^([0-9a-zA-Z_]+):\ ([0-9]+)\ windows/
	sess_list=command("list-sessions 2>&1",[],nil).chomp.lines.reject { |l| l.match /(^$|^no\ server\ running)/ }
	sess_list.each do |s|
		m=s.match sess_rx
		next if m.nil?
		#puts m.inspect
		sess,count=m[1],m[2]
		@sessions[sess]={} if @sessions[sess].nil?
		@sessions[sess]={:window_count=>count }
		get_windows(sess)
		end
	y=YAML.dump(@sessions)
	dputs y,10
  end

  def get_windows(sess=@session)
	# tmux list-windows -t yo
	# 1: bash* (1 panes) [205x71] [layout b71e,205x71,0,0,1] @1 (active)
	win_rx=/^([0-9a-zA-Z_]+):\ ([A-Za-z0-9\+_\-\*]+)\ \(([0-9]+)\ panes\)/
	win_list=command("list-windows -t #{sess}",[],nil).chomp.lines.reject { |l| l.match /(^$|^no\ server\ running)/ }
	win_list.each do |s|
		m=s.match win_rx
		dputs "line: '#{s.chomp}' \nwin_rx: '#{win_rx.inspect}' \nmatch: '#{m.inspect}'",100
		dputs " ",100
		next if m.nil?
		win,name,pcount=m[1],m[2],m[3]
		active=(name.match /\*$/) ? true : false
		@sessions[sess]={} if @sessions[sess].nil?
		@sessions[sess][:windows]={} if @sessions[sess][:windows].nil?
		@sessions[sess][:windows][win]={} if @sessions[sess][:windows][win].nil?
		@sessions[sess][:windows][win][:pane_count]=pcount 
		@sessions[sess][:windows][win][:name]=name
		@sessions[sess][:windows][win][:active]=active
		get_panes(sess,win)
		end
  end

  def get_panes(sess,win=0)
	# 2: [102x35] [history 0/2000, 0 bytes] %4 (active)
	pane_rx=/^([0-9]+):\ \[([0-9x]+)\]\ \[history\ [a-z0-9\/,\ ]+\]\ [%0-9]+(\ \(active\))?/
	pane_list=command("list-panes",[],win).chomp.lines.reject { |l| l.match /(^$|^no\ server\ running)/ }
	pane_list.each do |p|
		m=p.match pane_rx
		dputs "line: '#{p.chomp}' \npane_rx: '#{pane_rx.inspect}' \nmatch: '#{m.inspect}'",100
		next if m.nil?
		pain,size,act=m[1],m[2],m[3]
		dputs "win: #{win}, pane: #{pain}, size: #{size},act: '#{act.inspect}'",100
		dputs " "
		active=(act.nil? or act.empty? ) ? false : true
		@sessions[sess]={} if @sessions[sess].nil?
		@sessions[sess][:windows]={} if @sessions[sess][:windows].nil?
		@sessions[sess][:windows][win][:panes]={} if @sessions[sess][:windows][win][:panes].nil?
		@sessions[sess][:windows][win][:panes][pain]={:size=>size,:active=>active}
		end
  end


	#	command abstractions:

  def psync(window="0")
	state=(@synced==true) ? "off" : "on"
	command("set-window-option",["synchronize-panes",state],win(window))
	@synced=!@synced
  end

  def new_window
	dputs "sessions: #{@sessions}\nsession:#{@session}"
	#dputs "last window: #{@sessions[@session][:windows].keys,inspect}"
	if @sessions.keys.include? @session
		dputs "last window: #{@sessions[@session][:windows].keys.inspect}" if !@sessions[@session][:windows].nil?
		win=(@sessions[@session][:windows].keys.last.to_i+1).to_s
	else
		raise "failed to get new session '#{@tm_name}' \nsession: #{@session}\nsessions: #{@sessions.keys.inspect}"
		#
		#	new session
		win=(@sessions[@session][:windows].keys.last.to_i+1).to_s
	end
	name="#{@tm_name}-"+win
	command("new-window",["-a","-n '#{name}'"],@session)
	win
  end

  def layout(window="0",lo=@default_layout)
	#	even-horizontal, even-vertical, main-horizontal, main-vertical, or tiled
	command("select-layout",[lo],win(window))
  end

  def split(w=0,p=0)
	command("split-window",[],pane(w,p))
  end

  def make_panes(num,w=0,p=0)
	1.upto(num - 1) {|n| split(w,p)}
  end

	#

  def ssh_hpp(h=nil)
	hosts(h) if !h.nil?
	raise "no hosts set !" if !defined(@hosts) or @hosts.nil? or @hosts.empty?
	raise "no user set !" if !defined(@user) or @user.nil?
	get_sessions
	required=@hosts.count
	case window_selection
		when :new
			w=new_window()
			make_panes(required,w) 
		when :replace, :all
			need=(@sessions[@session][:windows][@window][:pane_count] - required)
			make_panes(need,@window) if need>0
		end
	was_synced=@synced
	psync if @synced
	@hosts.each_index do |hi|
		h=@hosts[hi]
		pane_cmd("ssh -l #{@user} #{h}",hi)
		end
  end


  def test(w)
	#make_panes(3,w)
	puts @sessions.inspect
	w=new_window()
	make_panes(4,w)
	layout(w)
  end


end
