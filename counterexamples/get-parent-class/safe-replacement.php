<?php
// The hand replacement: get_parent_class(self::class) returns what the
// no-argument call returned, in a class, a subclass and a trait, with no
// deprecation on any version.

class NoParent
{
    public function parentName()
    {
        return get_parent_class(self::class);
    }
}

class Base
{
}

class Child extends Base
{
    public function parentName()
    {
        return get_parent_class(self::class);
    }
}

class GrandChild extends Child
{
}

trait Names
{
    public function traitParent()
    {
        return get_parent_class(self::class);
    }
}

class UsesTraitWithParent extends Base
{
    use Names;
}

class UsesTraitNoParent
{
    use Names;
}

var_dump(
    (new NoParent())->parentName(),
    (new Child())->parentName(),
    (new GrandChild())->parentName(),
    (new UsesTraitWithParent())->traitParent(),
    (new UsesTraitNoParent())->traitParent()
);
