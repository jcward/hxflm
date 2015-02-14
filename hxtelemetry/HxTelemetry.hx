package hxtelemetry;

import sys.net.Socket;
import amf.io.Amf3Writer;
import haxe.ds.StringMap;

#if cpp
  import cpp.vm.Thread;
#end

class Config
{
  public var app_name:String = "My App";
  public var host:String = "localhost";
  public var port:Int = 7934;
  public var auto_event_loop:Bool = true;
  public var cpu_usage:Bool = true;
  public var profiler:Bool = true;
  public var allocations:Bool = true;
  public var singleton_instance:Bool = true;
}

class Timing {
  // Couldn't get an enum to work well wrt scope/access, still needed toString() anyway

  // Scout compatibility issue - real names
  public static inline var GC:String = ".gc.custom";
  public static inline var USER:String = ".as.doactions";
  public static inline var RENDER:String = ".rend.custom";
  public static inline var OTHER:String = ".other.custom";
  public static inline var NET:String = ".net.custom";
  public static inline var ENTER:String = ".enter";
  // CUSTOM(s:String, color:Int); // TODO: implement me? Sounds cool!
}

class HxTelemetry
{
  // Optional: singleton accessors
  public static var singleton(default,null):HxTelemetry;

  // Member objects
  var _config:Config;
  var _writer:Thread;
  var _thread_num:Int;

  // Timing helpers
  static var _abs_t0_usec:Float = Date.now().getTime()*1000;
  static inline function timestamp_ms():Float { return _abs_t0_usec/1000 + haxe.Timer.stamp()*1000; };
  static inline function timestamp_us():Float { return _abs_t0_usec + haxe.Timer.stamp()*1000000; };

  public function new(config:Config=null)
  {
    if (config==null) config = new Config();
    _config = config;

    if (_config.singleton_instance) {
      if (singleton!=null) throw "Cannot have two singletons of HxTelemetry!";
      singleton = this;
    }

    _writer = Thread.create(start_writer);
    _writer.sendMessage(Thread.current());
    _writer.sendMessage(config.host);
    _writer.sendMessage(config.port);
    _writer.sendMessage(config.app_name);
    if (!Thread.readMessage(true)) {
      _writer = null;
      return;
    }

    _method_names = new Array<String>();
    _samples = new Array<Int>();
    _alloc_types = new Array<String>();
    _alloc_details = new Array<Int>();
    _alloc_stackidmap = new Array<Int>();
    _collections = new Array<Int>();

#if cpp
    if (_config.allocations && !_config.profiler) {
      throw "HxTelemetry config.allocations requires config.profiler";
    }

    if (_config.profiler) {
#if !HXCPP_STACK_TRACE
      throw "Using the HXTelemetry Profiler requires -D HXCPP_STACK_TRACE or in project.xml: <haxedef name=\"HXCPP_STACK_TRACE\" />";
#end
      _thread_num = untyped __global__.__hxcpp_hxt_start_telemetry(_config.profiler, _config.allocations);
    }
#end

    if (config.auto_event_loop) setup_event_loop();
  }

  function setup_event_loop():Void
  {
#if openfl
    flash.Lib.stage.addEventListener("HXT_BEFORE_FRAME", advance_frame);
#elseif lime
    trace("Does lime have an event loop?");
#else
    trace("TODO: create separate thread for event loop? e.g. commandline tools");
#end
  }

  var _method_names:Array<String>;
  var _samples:Array<Int>;
  var _alloc_types:Array<String>;
  var _alloc_details:Array<Int>;
  var _alloc_stackidmap:Array<Int>;
  var _collections:Array<Int>;
  public function advance_frame(e=null)
  {
    if (_writer==null) return;

#if cpp
    untyped __global__.__hxcpp_hxt_ignore_allocs(1);
    if (_config.profiler) {
      untyped __global__.__hxcpp_hxt_stash_telemetry();
    }
    _writer.sendMessage({"dump":true, "thread_num":_thread_num});

    // // TODO: only send if they change, track locally
    // // TODO: support other names, reserved, etc
    // var gctotal:Int = Std.int((untyped __global__.__hxcpp_gc_reserved_bytes())/1024);
    // _writer.sendMessage({"name":".mem.total","value":gctotal });
    // _writer.sendMessage({"name":".mem.used","value":gctotal });

    // var gctime:Int = untyped __global__.__hxcpp_hxt_dump_gctime();
    // if (gctime>0) {
    //   _writer.sendMessage({"name":Timing.GC,"delta":gctime,"span":gctime});
    // }

    untyped __global__.__hxcpp_hxt_ignore_allocs(-1);
#end

    end_timing(Timing.ENTER);
  }

  var _last = timestamp_us();
  var _start_times:StringMap<Float> = new StringMap<Float>();
  public function start_timing(name:String):Void
  {
    if (_writer==null) return;

    var t = timestamp_us();
    _start_times.set(name, t);
  }
  public function end_timing(name:String):Void
  {
    if (_writer==null) return;

#if cpp
    untyped __global__.__hxcpp_hxt_ignore_allocs(1);
#end
    var t = timestamp_us();
    var data:Dynamic = {"name":name,"delta":Std.int(t-_last)}
    if (_start_times.exists(name)) {
      data.span = Std.int(t-_start_times.get(name));
    }
    _writer.sendMessage(data);
    _last = t;
#if cpp
    untyped __global__.__hxcpp_hxt_ignore_allocs(-1);
#end
  }


    @:functionCode('
printf("Dumping telemetry from thread %d\\n", thread_num);
TelemetryFrame* frame = __hxcpp_hxt_dump_telemetry(thread_num);
printf("Num samples %d\\n", frame->samples->size());
printf("New names %d\\n", frame->names->length);

output->writeByte(1); // names
output->writeInt32(frame->names->length); // names


// hx::Anon __result = hx::Anon_obj::Create();
// __result->Add(HX_CSTRING("name") , HX_CSTRING(".swf.name"),false);
// __result->Add(HX_CSTRING("value") , app_name,false);
// __result->Add(HX_CSTRING("hxt") , switch_to_nonamf,false);

//   ::haxe::Serializer s = ::haxe::Serializer_obj::__new();
//   s->serialize(frameData);
//  
//  
// output->writeString(s->toString());

')
    private static function test2(thread_num:Int, output:haxe.io.Output) {
      var arr:Array<String> = null;
      for (i in 0...arr.length) {
        trace(arr[i]);
      }

      // Examples
      //output.writeString("From haxe!");
      //output.writeInt32(12);
      //output.writeByte(45);
      // var arr:Array<UInt> = new Array<UInt>();
      // arr.push(2);
			// arr.push(4);
      // trace(arr.length);
      //  
      // var foo:Dynamic = {};
      // foo.n = 12;
      // foo.flt = 1.23;
      // foo.samples = new Array<Int>();
      // foo.im = new haxe.ds.IntMap<Dynamic>();
      // foo.im[12] = { type:"String", stackid:12, size:85, ids:(new Array<Int>()) };

      //untyped __global__.__hxcpp_hxt_ignore_allocs(1);
      // 
      //var frameData:Dynamic = untyped __global__.__hxcpp_hxt_dump_telemetry(thread_num);
      // 
      //// These are too large, they crash serializer...
      //Reflect.setField(frameData, "allocations", null);
      //Reflect.setField(frameData, "collections", null);
      // 
      //var b = haxe.io.Bytes.alloc(128);
      //b.set(0, 10);
      //b.set(1, 11);
      // 
      //var bd = new haxe.io.BytesData();
      //bd.blit();
      // 
      //var msg:String = haxe.Serializer.run(frameData);
      // 
      //trace(msg.length);
      // 
      //untyped __global__.__hxcpp_hxt_ignore_allocs(-1);

    }

  private static function start_writer():Void
  {
    var socket:Socket = null;
    var writer:Amf3Writer;

    var hxt_thread:Thread = Thread.readMessage(true);
    var host:String = Thread.readMessage(true);
    var port:Int = Thread.readMessage(true);
    var app_name:String = Thread.readMessage(true);

    function cleanup()
    {
      if (socket!=null) {
        socket.close();
        socket = null;
      }
      writer = null;
    }

    var switch_to_nonamf = true;
    var amf_mode = true;

    function safe_write(data:Dynamic) {
      try {
        if (!amf_mode) {
          var msg:String = haxe.Serializer.run(data);
          socket.output.writeInt32(msg.length);
          socket.output.writeString(msg);
        } else {
          writer.write(data);
        }
      } catch (e:Dynamic) {
        cleanup();
      }
    }

    socket = new Socket();
    try {
      socket.connect(new sys.net.Host(host), port);
      if (amf_mode) {
        writer = new Amf3Writer(socket.output);
      }
      safe_write({"name":".swf.name","value":app_name, "hxt":switch_to_nonamf});
      if (switch_to_nonamf) amf_mode = false;
      hxt_thread.sendMessage(true);
    } catch (e:Dynamic) {
      trace("Failed connecting to Telemetry host at "+host+":"+port);
      hxt_thread.sendMessage(false);
    }

    while (true) {
      // TODO: Accept timing data, too
      var data:Dynamic = Thread.readMessage(true);
      if (data.dump) {
        var thread_num:Int = data.thread_num;
        //trace("Calling dump telemetry with thread_num: "+thread_num+", socket.output="+socket.output);
        // TODO: @:function cpp dump telemetry, write to socket?  Read directly from cpp data structure?

        untyped __global__.__hxcpp_hxt_ignore_allocs(1);

        test2(thread_num, socket.output);

        //untyped __global__.__hxcpp_hxt_dump_telemetry(thread_num, socket.output);
        //Reflect.setField(frameData, "allocations", null);
        //Reflect.setField(frameData, "collections", null);
        //safe_write(frameData);

        untyped __global__.__hxcpp_hxt_ignore_allocs(-1);
      } else {
        safe_write(data);
      }
    }
    trace("HXTelemetry socket thread exiting");
  }
}
