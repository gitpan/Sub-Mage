package Sub::Mage;

=head1 NAME

Sub::Mage - Override, Restore and manipulate subroutines on-the-fly, without magic.

=head1 DESCRIPTION

On the very rare occasion you may need to override a subroutine for any particular reason. This module will help you do that 
with minimal fuss. Afterwards, when you're done, you can simply restore the subroutine back to its original state. 
Used on its own will override/restore a sub from the current script, but called from a class it will alter that classes subroutine. As long 
as the current package has access to it, it may be altered. 
Sub::Mage now has the ability to manipulate subroutines by creating C<after> and C<before> modifier hooks, or create new subroutines on the go with 
C<conjur>. New debugging functionality has been added also. With C<sub_alert> you can see when any subroutines (not Sub::Mage imported ones) are being 
called.

=head1 SYNOPSIS

    # Single file

    use Sub::Mage;

    sub greet { print "Hello, World!"; }

    greet; # prints Hello, World!

    override 'greet' => sub {
        print "Goodbye, World!";
    };

    greet; # now prints Goodbye, World!

    restore 'greet'; # restores it back to its original state

Changing a class method, by example

    # Foo.pm

    use Sub::Mage;

    sub new { my $self = {}; return bless $self, __PACKAGE__; }

    sub hello {
        my $self = shift;

        $self->{name} = "World";
    }

    # test.pl

    use Foo;

    my $foo = Foo->new;

    Foo->override( 'hello' => sub {
        my $self = shift;

        $self->{name} = "Town";
    });

    print "Hello, " . $foo->hello . "!\n"; # prints Hello, Town!

    Foo->restore('hello');

    print "Hello, " . $foo->hello . "!\n"; # prints Hello, World!

=cut

$Sub::Mage::VERSION = '0.005';
$Sub::Mage::Subs = {};
$Sub::Mage::Imports = [];
$Sub::Mage::Debug = 0;

use feature ();

sub import {
    my ($class, @args) = @_;
    my $pkg = caller;
    
    my $moosed;
    if (@args > 0) {
        for (@args) {
            feature->import( ':5.10' )
                if $_ eq ':5.010';
            
            _debug_on()
                if $_ eq ':Debug';
            
            _setup_class($pkg)
                if $_ eq ':Class';
            
            $moosed = 1
                if $_ eq ':Moose';
        }
    }

    if ($moosed) {
        _import_def(
            $pkg,
            qw/
                conjur
                sub_alert
            /,
        );
    }
    else {
        _import_def(
            $pkg,
            qw/
                override
                restore
                after
                before
                conjur
                sub_alert
            /,
        );
    }
}

sub _setup_class {
    my $class = shift;

    *{ "$class\::new" } = sub { return bless { }, $class };
}

sub _import_def {
    my ($pkg, @subs) = @_;

    for (@subs) {
        *{$pkg . "::$_"} = \&$_;
        push @{$Sub::Mage::Imports}, $_;
    }
}

sub override {
    my ($pkg, $name, $sub) = @_;

    if (scalar @_ > 2) {
        ($pkg, $name, $sub) = @_;
    }
    else {
        ($name, $sub) = ($pkg, $name);
        $pkg = caller;
    }

    my $warn = 0;
    if (! $pkg->can($name)) {
        warn "Cannot override a subroutine that doesn't exist";
        $warn = 1;
    }

    if ($warn == 0) {
        _debug("Override called for sub '$name' in package '$pkg'");
 
        _add_to_subs("$pkg\:\:$name");
        *$name = sub { $sub->(@_) };
        *{$pkg . "::$name"} = \*$name;
    }
}

sub _add_to_subs {
    my $sub = shift;

    if (! exists $Sub::Mage::Subs->{$sub}) {
        $Sub::Mage::Subs->{$sub} = {};
        $Sub::Mage::Subs->{$sub} = \&{$sub};
        _debug("$sub does not exist. Adding to Subs list\n");
    }
}

sub restore {
    my ($pkg, $sub) = @_;

    if (scalar @_ > 1) {
        my ($pkg, $sub) = @_;
    }
    else {
        $sub = $pkg;
        $pkg = caller;
    }

    $sub = "$pkg\:\:$sub";
    
    if (! exists $Sub::Mage::Subs->{$sub}) {
        _debug("Failed to restore '$sub' because it's not in the Subs list. Was it overriden or modified by a hook?");
        warn "I have no recollection of '$sub'";
        return 0;
    }

    *{$sub} = $Sub::Mage::Subs->{$sub};
    _debug("Restores sub $sub");
}

sub after {
    my ($pkg, $name, $sub) = @_;

    if (scalar @_ > 2) {
        ($pkg, $name, $sub) = @_;
    }
    else {
        ($name, $sub) = ($pkg, $name);
        $pkg = caller;
    }

    $full = "$pkg\:\:$name";
    my $alter_sub;
    my $new_code;
    my $old_code;
    die "Could not find $name in the hierarchy for $pkg\n"
        if ! $pkg->can($name);

    $old_code = \&{$full};
    *$name = sub {
        $old_code->(@_);
        $sub->(@_);
    };
    
    _add_to_subs($full);
    *{$full} = \*$name;
    _debug("Added after hook modified to '$name'");
}

sub before {
    my ($pkg, $name, $sub) = @_;

    if (scalar @_ > 2) {
        ($pkg, $name, $sub) = @_;
    }
    else {
        ($name, $sub) = ($pkg, $name);
        $pkg = caller;
    }

    $full = "$pkg\:\:$name";
    my $alter_sub;
    my $new_code;
    my $old_code;
    die "Could not find $name in the hierarchy for $pkg\n"
        if ! $pkg->can($name);

    $old_code = \&{$full};
    *$name = sub {
        $sub->(@_);
        $old_code->(@_);
    };

    _add_to_subs($full);
    *{$full} = \*$name;
    _debug("Added before hook modifier to $name");
}

sub conjur {
    my ($pkg, $name, $sub) = @_;

    if (scalar @_ > 2) {
        ($pkg, $name, $sub) = @_;
    }
    else {
        ($name, $sub) = ($pkg, $name);
        $pkg = caller;
    }

    my $warn = 0;
    if ($pkg->can($name)) {
        warn "You can't conjur a subroutine that already exists. Did you mean 'override'?";
        $warn = 1;
    }
    
    if ($warn == 0) {
        my $full = "$pkg\:\:$name";
        *$name = sub { $sub->(@_); };

        *{$full} = \*$name;
        _debug("Conjured new subroutine '$name' in '$pkg'");
    }
}

sub sub_alert {
    my $pkg = shift;
    my $module = __PACKAGE__;

    for (keys %{$pkg . "::"}) {
        my $sub = $_;

        unless ($sub eq uc $sub) {
            $pkg->before($sub => sub { print "[$module/Sub Alert] '$sub' called from $pkg\n"; })
                unless grep { $_ eq $sub } @{$Sub::Mage::Imports};
        }
    }
}

sub _debug_on {
    $Sub::Mage::Debug = 1;
    _debug("Sub::Mage debugging ON");
}

sub _debug {
    print '[debug] ' . shift . "\n"
        if $Sub::Mage::Debug == 1;
}

=head1 INCANTATIONS

When you C<use Sub::Mage> there are currently a couple of options you can pass to it. One is C<:5.010>. This will import the 5.010 feature.. this has nothing to do 
with subs, but I like this module, so it's there. The other is C<:Debug>. If for some reason you want some kind of debugging going on when you override, restore, conjur 
or create hook modifiers then this will enable it for you. It can get verbose, so use it only when you need to.

    use Sub::Mage ':5.010';

    say "It works!";

    #--

    use Sub::Mage qw/:5.010 :Debug/;

    conjur 'asub' => sub { }; # notifies you with [debug] that a subroutine was conjured

Now with importing we can turn a perfectly normal package into a class, sort of. It saves you from creating C<sub new { ... }>

    # MyApp.pm
    package MyApp;

    use Sub::Mage qw/:5.010 :Class/;

    1;

    # test.pl
    my $foo = MyApp->new;

    MyApp->conjur( name => sub {
        my ($self, $name) = @_;

        $self->{name} = $name;
        say "Set name to $name";
    });

    MyApp->conjur( getName => sub { return shift->{name}; });

    $foo->name('World');

    say $foo->getName;

Above we created a basically blank package, passed :Class to the Sub::Mage import method, then controlled the entire class from C<test.pl>.

=head1 SPELLS

=head2 override

Overrides a subroutine with the one specified. On its own will override the one in the current script, but if you call it from 
a class, and that class is visible, then it will alter the subroutine in that class instead.
Overriding a subroutine inherits everything the old one had, including C<$self> in class methods.


    override 'subname' => sub {
        # do stuff here
    };

    # class method
    FooClass->override( 'subname' => sub {
        my $self = shift;

        # do stuff
    });

=head2 restore

Restores a subroutine to its original state.

    override 'foo' => sub { };

    restore 'foo'; # and we're back in the room

=head2 after

Adds an after hook modifier to the subroutine. Anything in the after subroutine is called directly after the original sub.
Hook modifiers can also be restored.

    sub greet { print "Hello, "; }
    
    after 'greet' => sub { print "World!"; };

    greet(); # prints Hello, World!

=head2 before

Very similar to C<after>, but calls the before subroutine, yes that's right, before the original one.

    sub bye { print "Bye!"; }

    before 'bye' => sub { print "Good "; };

    bye(); # prints Good Bye!

=head2 conjur

"Conjurs" a subroutine into the current script or a class. By conjur I just mean create. It will not allow you to override a subroutine 
using conjur.

    conjur 'test' => sub { print "In test\n"; }
    test;

    Foo->conjur( hello => sub {
        my ($self, $name) = @_;

        print "Hello, $name!\n";
    });

=head2 sub_alert

B<Very verbose>: Adds a before hook modifier to every subroutine in the package to let you know when a sub is being called. Great for debugging if you're not sure a method is being ran.

    __PACKAGE__->sub_alert;

    # define a normal sub
    sub test { return "World"; }

    say "Hello, " . test(); # prints Hello, World but also lets you know 'test' in 'package' was called.

=head1 AUTHOR

Brad Haywood <brad@geeksware.net>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
