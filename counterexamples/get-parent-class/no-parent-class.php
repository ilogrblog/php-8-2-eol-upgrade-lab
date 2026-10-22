<?php
// get_parent_class() with no arguments in a class that has no parent.
// PHP 8.2 returns false. Rector's rewrite to parent::class does not compile.

class NoParent
{
    public function parentName()
    {
        return get_parent_class();
    }
}

var_dump((new NoParent())->parentName());
