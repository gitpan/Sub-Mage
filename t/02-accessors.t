#!perl

package MyTest;
use Test::More;

BEGIN { use_ok 'Sub::Mage', ':Class' }
can_ok 'MyTest' => 'has';
has 'x' => ( is => 'ro', default => 7 );
is x(), 7; 

done_testing;




