<?php
// The same call inside a trait used by a class with no parent. Rector's
// rewrite to parent::class compiles, so php -l passes, and fails only
// when the method is called.

trait Names
{
    public function parentName()
    {
        return get_parent_class();
    }
}

class UsesTrait
{
    use Names;
}

var_dump((new UsesTrait())->parentName());
