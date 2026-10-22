<?php
// The original calls the safe replacement must match.

class NoParent
{
    public function parentName()
    {
        return get_parent_class();
    }
}

class Base
{
}

class Child extends Base
{
    public function parentName()
    {
        return get_parent_class();
    }
}

class GrandChild extends Child
{
}

trait Names
{
    public function traitParent()
    {
        return get_parent_class();
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
