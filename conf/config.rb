#
#
#	setup config
#
@basepath=File.dirname(File.dirname(File.expand_path(__FILE__)))+"/"
@libpath=@basepath+"lib/"
@config_path=@basepath+"conf/"
@data_path=@basepath+"data/"


#	requires:
require 'rubygems'
require 'yaml'
#
require @libpath+"/"+"tmcontrol.rb"












#
#
@user=ENV['USER']
time=Time.now.strftime('%m%d%Y.%H%M%S') 
@tm_name="tmux_control_#{time}"

#
#	Settings:
#
@debug_level=10

#
@sync_by_default="on"

##       even-horizontal, even-vertical, main-horizontal, main-vertical, or tiled
@default_layout="main-horizontal"
