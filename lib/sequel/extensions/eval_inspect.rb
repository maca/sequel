# The eval_inspect extension changes #inspect for Sequel::SQL::Expression
# subclasses to return a string suitable for ruby's eval, such that
#
#   eval(obj.inspect) == obj
#
# is true.  The above code is true for most of ruby's simple classes such
# as String, Integer, Float, and Symbol, but it's not true for classes such
# as Time, Date, and BigDecimal.  Sequel attempts to handle situations where
# instances of these classes are a component of a Sequel expression.

module Sequel
  module EvalInspect
    # Special case objects where inspect does not generally produce input
    # suitable for eval.  Used by Sequel::SQL::Expression#inspect so that
    # it can produce a string suitable for eval even if components of the
    # expression have inspect methods that do not produce strings suitable
    # for eval.
    def eval_inspect(obj)
      case obj
      when Sequel::SQL::Blob, Sequel::LiteralString, Sequel::SQL::ValueList
        "#{obj.class}.new(#{obj.inspect})"
      when Array
        "[#{obj.map{|o| eval_inspect(o)}.join(', ')}]"
      when Hash
        "{#{obj.map{|k, v| "#{eval_inspect(k)} => #{eval_inspect(v)}"}.join(', ')}}"
      when Time
        if RUBY_VERSION < '1.9'
          # Time on 1.8 doesn't handle %N (or %z on Windows), manually set the usec value in the string
          hours, mins = obj.utc_offset.divmod(3600)
          mins /= 60
          "#{obj.class}.parse(#{obj.strftime("%Y-%m-%dT%H:%M:%S.#{sprintf('%06i%+03i%02i', obj.usec, hours, mins)}").inspect})#{'.utc' if obj.utc?}"
        else
          "#{obj.class}.parse(#{obj.strftime('%FT%T.%N%z').inspect})#{'.utc' if obj.utc?}"
        end
      when DateTime
        # Ignore date of calendar reform
        "DateTime.parse(#{obj.strftime('%FT%T.%N%z').inspect})"
      when Date
        # Ignore offset and date of calendar reform
        "Date.new(#{obj.year}, #{obj.month}, #{obj.day})"
      when BigDecimal
        "BigDecimal.new(#{obj.to_s.inspect})"
      else
        obj.inspect
      end
    end
  end

  extend EvalInspect

  module SQL
    class Expression
      # Attempt to produce a string suitable for eval, such that:
      #
      #   eval(obj.inspect) == obj
      def inspect
        # Assume by default that the object can be recreated by calling
        # self.class.new with any attr_reader values defined on the class,
        # in the order they were defined.
        klass = self.class
        args = inspect_args.map do |arg|
          if arg.is_a?(String) && arg =~ /\A\*/
            # Special case string arguments starting with *, indicating that
            # they should return an array to be splatted as the remaining arguments
            send(arg.sub('*', '')).map{|a| Sequel.eval_inspect(a)}.join(', ')
          else
            Sequel.eval_inspect(send(arg))
          end
        end
        "#{klass}.new(#{args.join(', ')})"
      end

      private

      # Which attribute values to use in the inspect string.
      def inspect_args
        self.class.comparison_attrs
      end
    end

    class ComplexExpression
      private

      # ComplexExpression's initializer uses a splat for the operator arguments.
      def inspect_args
        [:op, "*args"]
      end
    end

    class CaseExpression
      private

      # CaseExpression's initializer checks whether an argument was
      # provided, to differentiate CASE WHEN from CASE NULL WHEN, so
      # check if an expression was provided, and only include the
      # expression in the inspect output if so.
      def inspect_args
        if expression?
          [:conditions, :default, :expression]
        else
          [:conditions, :default]
        end
      end
    end

    class Function
      private

      # Function's initializer uses a splat for the function arguments.
      def inspect_args
        [:f, "*args"]
      end
    end

    class JoinOnClause
      private

      # JoinOnClause's initializer takes the on argument as the first argument
      # instead of the last.
      def inspect_args
        [:on, :join_type, :table, :table_alias] 
      end
    end

    class JoinUsingClause
      private

      # JoinOnClause's initializer takes the using argument as the first argument
      # instead of the last.
      def inspect_args
        [:using, :join_type, :table, :table_alias] 
      end
    end

    class OrderedExpression
      private

      # OrderedExpression's initializer takes the :nulls information inside a hash,
      # so if a NULL order was given, include a hash with that information.
      def inspect_args
        if nulls
          [:expression, :descending, :opts_hash]
        else
          [:expression, :descending]
        end
      end

      # A hash of null information suitable for passing to the initializer.
      def opts_hash
        {:nulls=>nulls} 
      end
    end
  end
end