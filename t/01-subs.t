#!perl -T

use Test::More;
use Sub::Mage;

sub test { "Test" }

override 'test' => sub { "World" };

is(test(), 'World', 'Is override actually overriding a subroutine?');

done_testing;
