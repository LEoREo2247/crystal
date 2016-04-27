require "../program"

module Crystal
  class Program
    def type_merge(types : Array(Type?))
      # Merging two types is the most common case, so we optimize it
      if types.size == 2
        first, second = types[0], types[1]
        did_merge, merged_type = type_merge_two(first, second)
        return merged_type if did_merge
      end

      combined_union_of compact_types(types)
    end

    def type_merge(nodes : Dependencies)
      # Merging two types is the most common case, so we optimize it
      if nodes.size == 2
        first, second = nodes.two!
        did_merge, merged_type = type_merge_two(first.type?, second.type?)
        return merged_type if did_merge
      end

      combined_union_of compact_types(nodes, &.type?)
    end

    def type_merge(nodes : Array(ASTNode))
      # Merging two types is the most common case, so we optimize it
      if nodes.size == 2
        first, second = nodes
        did_merge, merged_type = type_merge_two(first.type?, second.type?)
        return merged_type if did_merge
      end

      combined_union_of compact_types(nodes, &.type?)
    end

    def type_merge_two(first, second)
      if first == second
        # Same, so return any of them
        {true, first}
      elsif first
        if second
          # first and second not nil and different
          if first.opaque_id > second.opaque_id
            first, second = second, first
          end

          if first.nil_type?
            if second.is_a?(UnionType) && second.union_types.includes?(first)
              return true, second
            end
          end

          # puts "#{first} vs. #{second}"
          {false, nil}
        else
          # Second is nil, so return first
          {true, first}
        end
      else
        # First is nil, so return second
        {true, second}
      end
    end

    def type_merge_union_of(types : Array(Type))
      union_of compact_types(types)
    end

    def compact_types(types)
      compact_types(types) { |type| type }
    end

    def compact_types(objects)
      all_types = Array(Type).new(objects.size)
      objects.each { |obj| add_type all_types, yield(obj) }
      all_types.reject! &.no_return? if all_types.size > 1
      all_types
    end

    def add_type(types, type : UnionType)
      type.union_types.each do |subtype|
        add_type types, subtype
      end
    end

    def add_type(types, type : AliasType)
      add_type types, type.remove_alias
    end

    def add_type(types, type : Type)
      types << type unless types.includes? type
    end

    def add_type(set, type : Nil)
      # Nothing to do
    end

    def combined_union_of(types : Array)
      case types.size
      when 0
        nil
      when 1
        types.first
      else
        combined_types = type_combine types
        union_of combined_types
      end
    end

    def type_combine(types)
      all_types = [types.shift] of Type

      types.each do |t2|
        not_found = all_types.each do |t1|
          ancestor = t1.common_ancestor(t2)
          if ancestor
            all_types.delete t1
            all_types << ancestor.virtual_type
            break
          end
        end
        if not_found
          all_types << t2
        end
      end

      all_types
    end
  end

  class Type
    def self.merge(nodes : Dependencies)
      nodes.find(&.type?).try &.type.program.type_merge(nodes)
    end

    def self.merge(types : Array(Type))
      if types.size == 0
        nil
      else
        types.first.program.type_merge(types)
      end
    end

    def self.merge!(types_or_nodes)
      merge(types_or_nodes).not_nil!
    end

    def self.merge!(type1 : Type, type2 : Type)
      merge!([type1, type2])
    end

    def common_ancestor(other)
      nil
    end
  end

  class NonGenericModuleType
    def common_ancestor(other : Type)
      if other.implements?(self)
        self
      else
        nil
      end
    end
  end

  class GenericClassType
    def common_ancestor(other : Type)
      if other.implements?(self)
        self
      else
        nil
      end
    end
  end

  class ClassType
    def common_ancestor(other : ClassType)
      if depth <= 1
        return nil
      end

      if self == other
        return self
      end

      if struct?
        return nil
      end

      if depth == other.depth
        my_superclass = @superclass
        other_superclass = other.superclass

        if my_superclass && other_superclass
          return my_superclass.common_ancestor(other_superclass)
        end
      elsif depth > other.depth
        my_superclass = @superclass
        if my_superclass
          return my_superclass.common_ancestor(other)
        end
      elsif depth < other.depth
        other_superclass = other.superclass
        if other_superclass
          return common_ancestor(other_superclass)
        end
      end

      nil
    end

    def common_ancestor(other : VirtualType)
      common_ancestor(other.base_type)
    end

    def common_ancestor(other : NonGenericModuleType)
      other.common_ancestor(self)
    end
  end

  class MetaclassType
    def common_ancestor(other : MetaclassType)
      if instance_type.module? || other.instance_type.module?
        nil
      else
        common = instance_type.common_ancestor(other.instance_type)
        common.try &.metaclass
      end
    end
  end

  class PrimitiveType
    def common_ancestor(other)
      nil
    end
  end

  class VirtualType
    def common_ancestor(other)
      base_type.common_ancestor(other)
    end
  end

  class VirtualMetaclassType
    def common_ancestor(other)
      common = instance_type.base_type.metaclass.common_ancestor(other)
      common.try &.virtual_type!
    end
  end

  class TupleInstanceType
    def common_ancestor(other)
      if other.is_a?(TupleInstanceType) && self.size == other.size
        # We try to find the common ancestor of a tuple type with another tuple
        # type by either using the tuple's type if it's common to both tuples,
        # or by using the common ancestor (for example when merging
        # Foo and Bar < Foo we get Foo+). We don't merge unrelated types
        # (merging {Int32} and {String} will give {Int32} | {String}, not {Int32 | String})
        result_types = tuple_types.map_with_index do |self_tuple_type, index|
          other_tuple_type = other.tuple_types[index]
          if self_tuple_type == other_tuple_type
            self_tuple_type
          else
            ancestor = self_tuple_type.common_ancestor(other_tuple_type)
            return nil unless ancestor
            ancestor.virtual_type
          end
        end
        return program.tuple_of(result_types)
      end
      nil
    end
  end
end
