{spawn, exec} = require 'child_process'
fs = require 'fs'
_ = require 'underscore'

###
Base class for BuildTargets provider.

Derive your build targets providers from this class.
###
class BuildTargetsProvider

  # may be null, a string or a list of build files relative to root of current
  # project
  buildFiles: null

  constructor: (@builder) ->
    @commands = {}
    @root = builder.root
    @installWatcher()
    @update()

  # installs watch on files in buildFiles
  installWatcher: ->
    if @buildFiles?
      if not (@buildFiles instanceof Array)
        @buildFiles = [ @buildFiles ]

      for f in @buildFiles
        buildfile = "#{@root}/#{f}".replace(/\/\/+/, "/")
        fs.watchFile buildfile, => @update()

  # for each buildfile in @buildFiles, there is run `handler` on each file
  #
  # absolute path of buildfile is passed to handler and  handler must return
  # an object.  either empty or it contains a dictionary
  # of command (which is something like "build:buildtoolname-targetname")
  #
  # Value may be one of the following:
  # 1. Build System
  # 2. function
  # 3. args (either a single string for one arg or an Array)
  #
  buildFile: (handler)->
    return {} if not @buildFiles?

    handle = handler

    commands = {}
    for f in @buildFiles
      buildfile = "#{@root}/#{f}".replace(/\/\/+/, "/")
      _.extend(commands, handle buildfile) if fs.existsSync buildfile

    return commands

  # returns build command, which is used for creating atom commands
  buildSystem: (name) ->
    if name instanceof Array
      (new BuildSystem builder: @builder, cmd: @buildTool, args: name).build
    else
      (new BuildSystem builder: @builder, cmd: @buildTool, args: [name]).build

  # implement this function to return a dictionary like described in buildFile
  #
  # usually you would implemnt it like this:
  #
  #    getCommands: ->
  #        @buildFile (buildfile) =>
  #            # now do something with build file
  getCommands: -> {}

  # is called from watcher on file change
  update: -> @replaceCommands(@getCommands())

  # replaces commands for build targets with new ones
  replaceCommands: (commands) ->
    for k,v of @commands
      if not k of commands
        @removeCommand k

    for k,v of commands
      if v instanceof BuildSystem
        @addCommand k, v.build
      if typeof v is "function"
        @addCommand k, (new BuildSystem builder: @builder, build: v).build
      else
        @addCommand k, @buildSystem v

  # adds command to atom workspace
  addCommand: (name, command) ->
    @commands[name] = command
    @builder.addCommand name, command
    #@builder.atom.workspaceView.command name, command

  # removes command from atom workspace
  removeCommand: (name) ->
    if @commands[name]
      @builder.removeCommand name

      # @builder.atom.workspaceView.off name
      # # see space-pen jQuery extensions
      # data = @builder.atom.workspaceView.data('documentation')
      # if data?.name?
      #     delete data[name]
      #
      delete @commands[name]

  # run buildTool and call gotline for each line from output of buildTool
  #
  # opts may have cwd, args keys and whatever child_process.exec accepts.
  # args must be an array.
  getLines: (opts, gotline) ->
    if opts typeof "function"
      opts = {}
      gotline = opts

    exec_opts =
      cwd: @root

    $.extend exec_opts, opts

    cmd = @buildTool
    if exec_opts.args
      cmd += " " + " ".join(exec_opts.args)
      delete exec_opts.args

    exec cmd, exec_opts, (error, stdout, stderr) ->
      lines = stdout.toString().replace(/\n$/, '').split(/\n/)
      for line in lines
        gotline(line)

# first register all classes and later activate it on package activation
class BuildTargetProviderRegistry
  constructor: ->
    @registry = []
    @containers = []
    @buildsystems = []

  register: (thing) ->
    if thing instanceof BuildSystem
      @buildsystems.push thing
    else
      @registry.push thing

  activate: (builder) ->
    for buildTargetsProvider in @registry
      @containers.push new buildTargetsProvider(builder)

###
This class is passed as opts to builder's startNewBuild function

Not yet all supported, what you see here.  What definitely is supported is

- cmd
- args
- cwd
###

class BuildSystem

  constructor: (opts) ->

    # sublime text opts (see http://sublime-text-unofficial-documentation.readthedocs.org/en/latest/reference/build_systems.html)
    {@file_regex, @cmd, @selector, @line_regex, @working_dir} = opts
    {@encoding, @env, @shell, @path, @syntax} = opts

    # atom's protocol opts
    {@args, @cwd, @builder, @build} = opts

    if @cmd instanceof Array
      @args = cmd[1..]
      @cmd  = cmd[0]

    if @working_dir? and !@cwd
      @cwd = @working_dir

    if !@build
      @build = => @builder.startNewBuild this

module.exports =
  BuildTargets: BuildTargets
  buildRegistry: new BuildTargetsRegistry()
  BuildSystem: BuildSystem
