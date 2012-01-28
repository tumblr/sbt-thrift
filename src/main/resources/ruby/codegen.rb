#!/usr/bin/env ruby

# This is the scala codegen.  It works by reflecting The generated ruby.

$VERBOSE = nil # Ruby thrift bindings always are noisy

require "fileutils"
require "erb"
require "set"
include FileUtils

# Stub out thrift.  We just need to have the generated ruby compile, not
# actually run in this context.
module ::Thrift
  module Client; end
  module Processor; end
  module Struct
    def generate_accessors(*args); end
    def method_missing(*args);end
    extend self
  end
  module Struct_Union; end
  module Types
    BOOL   = 0
    BYTE   = 1
    I16    = 2
    I32    = 3
    I64    = 4
    DOUBLE = 5
    STRING = 6
    MAP    = 7
    SET    = 8
    LIST   = 9
    STRUCT = 10
  end

  class Exception; end

  class ApplicationException
    MISSING_RESULT = nil
    def initialize(*args)
    end
  end
end

def require(*args);
  if ["thrift"].include?(args.first)
  else
    Kernel::require(*args)
  end
end

module Kernel
  def const_get_recursive(name)
    name.split("::").reject{|s| s.empty?}.inject(Kernel){|m, n| m.const_get(n) }
  end
end

class Class
  def const_find(name)
    klass = self
    while klass
      modul = "::" + klass.name.gsub(/::\w+$/, '')
      begin
        return const_get_recursive(modul + "::" + name)
      rescue
        # continue
      end
      klass = klass.superclass
    end
    raise "couldn't find #{name} around #{self.name}"
  end
end

# Utility stolen from activesupport
class String
  def camelize(first_letter_in_uppercase = false)
    if first_letter_in_uppercase
      gsub(/\/(.?)/) { "::#{$1.upcase}" }.gsub(/(?:^|_)(.)/) { $1.upcase }
    else
      self[0].chr.downcase + camelize(self)[1..-1]
    end
  end

  def capitalize
    self[0].chr.upcase + self[1..-1]
  end
end

# These functions are macros for common patterns in the generated scala.

def type_of(field, thrifty = false, nested = false)
  return "Void" if field.nil?
  j = thrifty && nested ? "java.lang." : ""
  base = case field[:type]
  when ::Thrift::Types::I32:
    if field[:enum_class]
      tnamespace = $tnamespace
      if last(field[:enum_class]).to_s == "Status"
        tnamespace = "com.twitter.thrift"
      end
      thrifty ?
      tnamespace + "." + last(field[:enum_class]) :
      last(field[:enum_class])
    else
      thrifty && nested ? "java.lang.Integer" : "Int"
    end
  when ::Thrift::Types::STRUCT: thrifty ? $tnamespace + "." + last(field[:class]) : last(field[:class])
  when ::Thrift::Types::STRING:
    field[:binary] ? "java.nio.ByteBuffer" : "String"
  when ::Thrift::Types::BOOL: "#{j}Boolean"
  when ::Thrift::Types::I16: "#{j}Short"
  when ::Thrift::Types::I64: "#{j}Long"
  when ::Thrift::Types::BYTE: "#{j}Byte"
  when ::Thrift::Types::DOUBLE: "#{j}Double"
  when ::Thrift::Types::SET:
    tmp = "Set[#{type_of(field[:element], thrifty, true)}]"
    thrifty ? "J#{tmp}" : tmp
  when ::Thrift::Types::MAP:
    tmp = "Map[#{type_of(field[:key], thrifty, true)}, #{type_of(field[:value], thrifty, true)}]"
    thrifty ? "J#{tmp}" : tmp
  when ::Thrift::Types::LIST:
    generic = "[#{type_of(field[:element], thrifty, true)}]"
    (thrifty ? "JList" : "Seq") + generic
  else
    throw "unknown field type: #{field[:type]}"
  end
  field[:optional] ? "Option[#{base}]" : base
end

def unwrapper(f, nested = false)
  pre = ""
  post = ""
  case f[:type]
  when ::Thrift::Types::DOUBLE:
    if nested
      pre += "new java.lang.Double("
      post += ")"
    end
  when ::Thrift::Types::I64:
    if nested
      pre += "new java.lang.Long("
      post += ")"
    end
  when ::Thrift::Types::BYTE:
    if nested
      pre += "new java.lang.Byte("
      post += ")"
    end
  when ::Thrift::Types::BOOL:
    if nested
      pre += "new java.lang.Boolean("
      post += ")"
    end
  when ::Thrift::Types::SET:
    pre += "asJavaSet(("
    a, b = unwrapper(f[:element], true)
    post += ").map(x => #{a}x#{b}))"
  when ::Thrift::Types::LIST:
    pre += "asJavaList(("
    a, b = unwrapper(f[:element], true)
    post += ").map(x => #{a}x#{b}))"
  when ::Thrift::Types::MAP:
    pre += "asJavaMap(("
    a, b = unwrapper(f[:key], true)
    c, d = unwrapper(f[:value], true)
    post += ").map(x => (#{a}x._1#{b}, #{c}x._2#{d})).toMap)"
  when ::Thrift::Types::I32:
    if f[:enum_class]
      post += ".toThrift"
    elsif nested
      pre += "new java.lang.Integer("
      post += ")"
    end
  when ::Thrift::Types::STRUCT:
    post += ".toThrift"
  end
  [pre, post]
end

def unwrap(f, inner = nil)
  pre, post = unwrapper(f)
  if inner
    pre + inner + post
  else
    @output << pre
    yield
    @output << post
  end
end

def wrapper(f, name = nil, nested = false)
  name ||= f[:name].camelize
  case f[:type]
  when ::Thrift::Types::I32:
    if f[:enum_class]
      "#{last(f[:enum_class])}(#{name})"
    else
      "#{name}.intValue"
    end
  when ::Thrift::Types::BYTE: "#{name}.byteValue"
  when ::Thrift::Types::I64: "#{name}.longValue"
  when ::Thrift::Types::BOOL: "#{name}.booleanValue"
  when ::Thrift::Types::DOUBLE: "#{name}.doubleValue"
  when ::Thrift::Types::LIST: "asScalaBuffer(#{name}).view.map(x=>#{wrapper(f[:element], "x", true)}).toList"
  when ::Thrift::Types::SET: "Set(asScalaSet(#{name}).view.map(x=>#{wrapper(f[:element], "x", true)}).toSeq: _*)"
  when ::Thrift::Types::MAP: "Map((#{name}).view.map(x=>(#{wrapper(f[:key], "x._1", true)}, #{wrapper(f[:value], "x._2", true)})).toSeq: _*)"
  when ::Thrift::Types::STRUCT: "new #{last(f[:class])}(#{name})"
  else
    name
  end
end

def last(klass)
  klass.to_s.split("::").pop
end

MStruct = Struct.new(:name, :args, :retval)

module Codegen
  def run(input, output_base, tnamespace, rnamespace, namespace, exception_class, do_idiomize)
    output = File.expand_path(File.join(output_base, *namespace.split(".")))
    mkdir_p output
    $tnamespace = tnamespace
    $exception_class = exception_class.empty? ? nil : exception_class

    $do_idiomize = do_idiomize
    def idiomize(m) $do_idiomize ? m.name.camelize : m.name end

    # Hooray, we generate the scala with ERb

    misc_template_string = <<-EOF
package com.twitter.sbt.thrift

abstract class ScalaThriftException extends Exception {
  def toThrift(): Exception
}
EOF

    dir = "#{output_base}/com/twitter/sbt/thrift"
    mkdir_p(dir)
    File.open("#{dir}/Misc.scala", "w") {|f| f.print(misc_template_string) }

    service_template_string = <<EOF
package <%=namespace %>

// Autogenerated

import java.net.InetSocketAddress
import java.util.{List => JList, Map => JMap, Set => JSet}
import scala.collection._
import scala.collection.JavaConversions._
import org.apache.thrift.protocol._
import org.apache.thrift.TApplicationException

import com.twitter.conversions.time._
import com.twitter.finagle.builder._
import com.twitter.finagle.stats._
import com.twitter.finagle.thrift._
import com.twitter.logging.Logger
import com.twitter.ostrich.admin.Service
import com.twitter.util._
import com.twitter.sbt.thrift._
import com.twitter.thrift.scala.Status
import com.twitter.finagle.stats.OstrichStatsReceiver

<% if extends_s.length > 0 %>
trait <%=obj%><%= extends_s %> {
  override implicit def voidUnit(f: Future[_]): Future[java.lang.Void] = f.map(x=>null)

  <% for m in methods do %>
    def <%=idiomize(m)%>(<%=m.args.map{|f| f[:name].camelize + ": " + type_of(f)}.join(", ") %>): Future[<%=type_of(m.retval)%>]
  <% end %>

  def toThrift = new <%=obj%>ThriftAdapter(this)
}
<% else %>
trait <%=obj%> {
  implicit def voidUnit(f: Future[_]): Future[java.lang.Void] = f.map(x=>null)

  <% for m in methods do %>
    def <%=idiomize(m)%>(<%=m.args.map{|f| f[:name].camelize + ": " + type_of(f)}.join(", ") %>): Future[<%=type_of(m.retval)%>]
  <% end %>

  def toThrift = new <%=obj%>ThriftAdapter(this)
}
<% end %>

trait <%=obj%>Server extends Service {
  val log = Logger.get(getClass)
  val serverName: String
  val service: <%=obj%>
  protected def defaultShutdownTimeout: Duration = 1.second
}

<% if extends_s.length > 0 %>
trait <%=obj%>ThriftServer extends <%=obj%>Server {

  def thriftCodec = ThriftServerFramedCodec()
  val thriftProtocolFactory = new TBinaryProtocol.Factory()
  val thriftPort: Int

  var server: Server = null

  def start = {
    val thriftImpl = new <%=tnamespace%>.<%=obj%>.Service(service.toThrift, thriftProtocolFactory)
    val serverAddr = new InetSocketAddress(thriftPort)
    server = ServerBuilder().codec(thriftCodec).name(serverName).reportTo(new OstrichStatsReceiver).bindTo(serverAddr).build(thriftImpl)
  }

  def shutdown = synchronized {
    if (server != null) {
      server.close(defaultShutdownTimeout)
    }
  }
}
<% else %>
trait <%=obj%>Server extends Service with <%=obj%>{
  val log = Logger.get(getClass)

  def thriftCodec = ThriftServerFramedCodec()
  val thriftProtocolFactory = new TBinaryProtocol.Factory()
  val thriftPort: Int
  val serverName: String

  var server: Server = null

  def start = {
    val thriftImpl = new <%=tnamespace%>.<%=obj%>.Service(toThrift, thriftProtocolFactory)
    val serverAddr = new InetSocketAddress(thriftPort)
    server = ServerBuilder().codec(thriftCodec).name(serverName).reportTo(new OstrichStatsReceiver).bindTo(serverAddr).build(thriftImpl)
  }

  def shutdown = synchronized {
    if (server != null) {
      server.close(defaultShutdownTimeout)
    }
  }
}
<% end %>

class <%=obj%>ThriftAdapter(val <%=obj.to_s.camelize%>: <%=obj%>) extends <%=tnamespace%>.<%=obj%>.ServiceIface {
  val log = Logger.get(getClass)
  def this() = this(null)

  <% for m in all_methods do %>
    def <%=m.name%>(<%=m.args.map{|f| f[:name].camelize + ": " + type_of(f, true)}.join(", ") %>) = {
      try {
        <%=obj.to_s.camelize%>.<%=idiomize(m)%>(<%=m.args.map{|f| wrapper(f) }.join(", ")%>)
        <% if m.retval %>
          .map[<%=type_of(m.retval, true, true)%>] { retval =>
            <% unwrap(m.retval) do %>retval<%end%>
          }
        <% end %>
        .handle {
          case t: ScalaThriftException => throw(t.toThrift())
          case t: Throwable => {
            log.error(t, "Uncaught error handled in <%=m.name%>: %s", t)
            throw new <%=$exception_class ? $exception_class : "TApplicationException"%>(t.getMessage)<%=".toThrift" if $exception_class %>
          }
        }
      } catch {
        case t: ScalaThriftException => throw(t.toThrift())
        case t: Throwable => {
          log.error(t, "Uncaught error caught in <%=m.name%>: %s", t)
          throw new <%=$exception_class ? $exception_class : "TApplicationException"%>(t.getMessage)<%=".toThrift" if $exception_class %>
        }
      }
    }
  <% end %>
}

class <%=obj%>ClientAdapter(val <%=obj.to_s.camelize%>: <%=tnamespace%>.<%=obj%>.ServiceIface) extends <%=obj%> {
  val log = Logger.get(getClass)
  def this() = this(null)

  <% for m in all_methods do %>
    def <%=idiomize(m)%>(<%=m.args.map{|f| f[:name].camelize + ": " + type_of(f)}.join(", ") %>) = {
      try {
        <%=obj.to_s.camelize%>.<%=m.name%>(<%=m.args.map{|f| unwrap(f, f[:name].camelize) }.join(", ")%>)
        <% if m.retval %>
          .map[<%=type_of(m.retval)%>] { retval =>
            <%=wrapper(m.retval, "retval") %>
          }
        <% end %>
        .handle {
          case t: ScalaThriftException => throw(t.toThrift())
          case t: Throwable => {
            log.error(t, "Uncaught error handled in <%=idiomize(m)%>: %s", t)
            throw new <%=$exception_class ? $exception_class : "TApplicationException"%>(t.getMessage)<%=".toThrift" if $exception_class %>
          }
        }
      } catch {
        case t: ScalaThriftException => throw(t.toThrift())
        case t: Throwable => {
          log.error(t, "Uncaught error caught in <%=idiomize(m)%>: %s", t)
          throw new <%=$exception_class ? $exception_class : "TApplicationException"%>(t.getMessage)<%=".toThrift" if $exception_class %>
        }
      }
    }
  <% end %>
}
EOF

    enum_template_string = <<EOF
package <%=namespace %>

// Autogenerated

abstract case class <%=obj%>(id: Int) {
  def name: String
  def toThrift = <%=tnamespace %>.<%=obj%>.findByValue(id)
}
object <%=obj%> {
  def apply(thrifty: <%=tnamespace %>.<%=obj%>): <%=obj%> = apply(thrifty.getValue)

  def apply(id: Int): <%=obj%> = id match {
    <% values.values.each do |v| %>
      case <%=v.downcase.camelize(true)%>.id => <%=v.downcase.camelize(true)%>
    <% end %>
  }

  def apply(name: String): <%=obj%> = name match {
    <% values.values.each do |v| %>
      case "<%=v.downcase.camelize(true)%>" => <%=v.downcase.camelize(true)%>
    <% end %>
  }

  <% values.each do |k, v| %>
    object <%=v.downcase.camelize(true)%> extends <%=obj%>(<%=k%>) {
      val name = "<%=v.downcase.camelize(true)%>"
    }
  <% end %>
}
EOF

    struct_template_string = <<EOF
package <%=namespace %>

import java.util.{List => JList, Map => JMap, Set => JSet}
import scala.collection._
import scala.collection.JavaConversions._
import com.twitter.sbt.thrift._

// Autogenerated

object <%=obj%> {
  def apply(thrifty: <%=tnamespace%>.<%=obj%>) = new <%=obj%>(thrifty)
}

case class <%=obj%>(<%=fields.map{|f|
    name = f[:name].camelize + ": " + type_of(f)
    if f[:optional]
      "\#{name} = None"
    elsif f[:default]
      if f[:enum_class]
        "\#{name} = \#{last f[:enum_class]}(\#{f[:default].inspect})"
      else
        "\#{name} = \#{f[:default].inspect}"
      end
    else
      name
    end
  }.join(", ") %>) <%="extends ScalaThriftException" if is_exception %>{
  def this(thrifty: <%=tnamespace%>.<%=obj%>) = this(
    <% for f in fields do %>
      <%="," unless f == fields.first %>
      <% if f[:optional] %>
        if(thrifty.isSet<%=f[:name].capitalize%>) {
          Some(<%= wrapper(f, "thrifty.\#{f[:name]}")%>)
        } else {
          None
        }
      <% else %>
        <%= wrapper(f, "thrifty.\#{f[:name]}")%>
      <% end %>
    <% end %>
  )

  <% if fields.any?{|f| f[:optional]} %>
    def this(<%=fields.map{|f| f[:name].camelize + ": " + type_of(f) unless f[:optional] }.compact.join(", ") %>) = this(<%=fields.map{|f| f[:optional] ? "None" : f[:name].camelize }.join(", ") %>)
  <% end %>

  def toThrift() = {
    val out = new <%=tnamespace%>.<%=obj%>()
    <% for f in fields do %>
      <%="\#{f[:name].camelize}.foreach { \#{f[:name].camelize} => " if f[:optional] %>
        out.set<%=f[:name].capitalize%>(<%unwrap(f) do %><%=f[:name].camelize%><% end %>)
      <%="}" if f[:optional] %>
    <% end %>
    out
  }
}
EOF

    constants_template_string = <<EOF
package <%=namespace %>

// Autogenerated

object Constants {
  <% constants.each do |name| %>
    val <%=name.downcase.camelize(true)%> = <%=root.const_get(name).inspect%>
  <% end %>
}
EOF

    # Load the thrift files
    $: << File.expand_path(input)
    Dir["#{input}/*types.rb"].each {|f| load f }
    Dir["#{input}/*.rb"].each {|f| load f }

    # Scan looking for...
    root = eval(rnamespace) || Kernel
    classes = root.constants.select{|c| root.const_get(c).respond_to?(:const_defined?)}
    constants = root.constants.reject{|c| root.const_get(c).respond_to?(:const_defined?)}

    if constants.size > 0
      template = ERB.new(constants_template_string, nil, nil, "@output")
      File.open("#{output}/Constants.scala", "w") {|f| f.print(template.result(binding)) }
    end

    classes.each do |name|
      obj = root.const_get(name)
      if obj.const_defined?(:VALUE_MAP)
        # I'm an enum
        values = obj::VALUE_MAP

        obj = last obj
        template = ERB.new(enum_template_string, nil, nil, "@output")
        File.open("#{output}/#{obj}.scala", "w") {|f| f.print(template.result(binding)) }
      end
    end

    classes.each do |name|
      obj = root.const_get(name)
      if obj.method_defined?(:struct_fields)
        fields = obj.new.struct_fields.to_a.sort_by{|f| f.first}.map{|f| f.last }
        # We assume that you'll have a single thrift exception type for your app.
        is_exception = obj.superclass == ::Thrift::Exception
        $exception = obj if is_exception

        obj = last obj
        template = ERB.new(struct_template_string, nil, nil, "@output")
        File.open("#{output}/#{obj}.scala", "w") {|f| f.print(template.result(binding)) }
      end
    end

    classes.each do |name|
      obj = root.const_get(name)
      if obj.const_defined?(:Client)
        client = obj.const_get(:Client)
        if client.superclass.to_s == "Twitter::Thrift::ThriftService::Client"
          extends_s = " extends com.twitter.thrift.scala.ThriftService"
        else
          extends_s = ""
        end
        methods = client.instance_methods(false).map {|m| m.to_s[/send_(.{3,})$/, 1] }.compact.map {|name|
          if name
            out = MStruct.new
            out.name = name
            out.args = client.const_find(name.capitalize + "_args").new.struct_fields.to_a.sort_by{|f| f.first}.map{|f| f.last }
            out.retval = client.const_find(name.capitalize + "_result").new.struct_fields[0]
            out
          end
        }
        all_methods = client.instance_methods.map {|m| m.to_s[/send_(.{3,})$/, 1] }.compact.map {|name|
          if name
            out = MStruct.new
            out.name = name
            out.args = client.const_find(name.capitalize + "_args").new.struct_fields.to_a.sort_by{|f| f.first}.map{|f| f.last }
            out.retval = client.const_find(name.capitalize + "_result").new.struct_fields[0]
            out
          end
        }
        obj = last obj
        template = ERB.new(service_template_string, nil, nil, "@output")
        File.open("#{output}/#{obj}.scala", "w") {|f|
          f.print(template.result(binding))
        }
      end
    end
  end
  extend self
end

if ARGV.length == 7
  Codegen::run(*ARGV)
end
