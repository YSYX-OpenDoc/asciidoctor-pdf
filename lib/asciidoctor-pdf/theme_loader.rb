require 'safe_yaml/load'
require 'ostruct'
require_relative 'core_ext/ostruct'

module Asciidoctor
module Pdf
class ThemeLoader
  DataDir = ::File.expand_path ::File.join(::File.dirname(__FILE__), '..', '..', 'data')
  ThemesDir = ::File.join DataDir, 'themes'
  FontsDir = ::File.join DataDir, 'fonts'
  HexColorValueRx = /_color: (?<quote>"|'|)#?(?<value>[A-Za-z0-9]{3,6})\k<quote>$/

  def self.resolve_theme_file theme_name = nil, theme_path = nil
    theme_name ||= 'default'
    # if .yml extension is given, assume it's a full file name
    if theme_name.end_with? '.yml'
      # FIXME restrict to jail!
      # QUESTION why are we not using expand_path in this case?
      theme_path ? (::File.join theme_path, theme_name) : theme_name
    else
      # QUESTION should we append '-theme.yml' or just '.yml'?
      ::File.expand_path %(#{theme_name}-theme.yml), (theme_path || ThemesDir)
    end
  end

  def self.resolve_theme_asset asset_path, theme_path = nil
    ::File.expand_path asset_path, (theme_path || ThemesDir)
  end

  def self.load_theme theme_name = nil, theme_path = nil
    load_file (resolve_theme_file theme_name, theme_path)
  end

  def self.load_file filename
    data = ::IO.read(filename).each_line.map {|l| l.sub(HexColorValueRx, '_color: \'\k<value>\'') }.join
    self.new.load(::SafeYAML.load(data))
  end

  def load hash
    hash.inject(::OpenStruct.new) do |s, (k, v)|
      if v.kind_of? ::Hash
        v.each do |k2, v2|
          s[%(#{k}_#{k2})] = (k2.end_with? '_color') ? to_hex(evaluate(v2, s)) : evaluate(v2, s)
        end
      else
        s[k] = (k.end_with? '_color') ? to_hex(evaluate(v, s)) : evaluate(v, s)
      end
      s
    end
  end

  private

  def evaluate expr, vars
    case expr
    when ::String
      evaluate_math(expand_vars(expr, vars))
    when ::Array
      expr.map {|e| evaluate(e, vars) }
    else
      expr
    end
  end
  
  def expand_vars expr, vars
    if expr.include? '$'
      if (expr.start_with? '$') && (expr.match /^\$([a-z0-9_]+)$/)
        vars[$1]
      else
        expr.gsub(/\$([a-z0-9_]+)/) { vars[$1] }
      end
    else
      expr
    end
  end
  
  def evaluate_math expr
    return expr unless ::String === expr
    original = expr
    # FIXME HACK turn a single negative number into an expression
    if expr.start_with? '-'
      expr = %(1 - #{expr[1..-1]})
    end
    while true
      # TODO move this regular expression to a constant
      result = expr.gsub(/(-?\d+(?:\.\d+)?) *([*\/]) *(-?\d+(?:\.\d+)?)/) { $1.to_f.send($2.to_sym, $3.to_f) }
      unchanged = (result == expr)
      expr = result
      break if unchanged
    end
    while true
      # TODO move this regular expression to a constant
      result = expr.gsub(/(-?\d+(?:\.\d+)?) *([+\-]) *(-?\d+(?:\.\d+)?)/) { $1.to_f.send($2.to_sym, $3.to_f) }
      unchanged = (result == expr)
      expr = result
      break if unchanged
    end
    if (expr.end_with? ')') && (expr.match /^(round|floor|ceil)\(/)
      op = $1
      offset = op.length + 1
      expr = expr[offset...-1].to_f.send(op.to_sym)
    end
    if original == expr
      expr
    else
      if ((int_val = expr.to_i) == (float_val = expr.to_f))
        int_val
      else
        float_val
      end
    end
  end

  def to_hex value
    str = value.to_s
    return str if str == 'transparent'
    hex = case str.size
    when 6
      str
    when 3
      str.each_char.map {|it| it * 2 }.join 
    else
      # CAUTION: YAML will misinterpret values with leading zeros (e.g., 000011) that are not quoted (aside from 000000)
      str[0..5].rjust(6, '0')
    end
    hex.upcase
  end
end
end
end
