package Sub::Mage;

=head1 NAME

Sub::Mage - Override, restore subroutines and add hook modifiers, with much more sugary goodness.

=head1 DESCRIPTION

On the very rare occasion you may need to override a subroutine for any particular reason. This module will help you do that 
with minimal fuss. Afterwards, when you're done, you can simply restore the subroutine back to its original state. 
Used on its own will override/restore a sub from the current script, but called from a class it will alter that classes subroutine. As long 
as the current package has access to it, it may be altered. 
Sub::Mage now has the ability to manipulate subroutines by creating C<after> and C<before> modifier hooks, or create new subroutines on the go with 
C<conjur>. New debugging functionality has been added also. With C<sub_alert> you can see when any subroutines (not Sub::Mage imported ones) are being 
called.
Sub::Mage now boasts more functionality than I can fit here. Please read the pod for more info.

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

$Sub::Mage::VERSION = '0.013';
$Sub::Mage::Subs = {};
$Sub::Mage::Imports = [];
$Sub::Mage::Classes = [];
$Sub::Mage::Debug = 0;

sub import {
    my ($class, @args) = @_;
    my $pkg = caller;
    
    my $moosed;
    if (@args > 0) {
        for (@args) {
            feature::feature->import( ':5.10' )
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
                duplicate
                exports
                have
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
                duplicate
                exports
                have
                around
            /,
        );
    }
}

sub augment {
    my (@classes) = @_;
    my $pkg = caller();
    
    if ($pkg eq 'main') {
        warn "Cannot augment main";
        return ;
    }

    _augment_class( \@classes, $pkg );
}

sub _augment_class {
    my ($mothers, $class) = @_;

    foreach my $mother (@$mothers) {
        # if class is unknown to us, import it (FIXME)
        unless (grep { $_ eq $class } @$Sub::Mage::Classes) {
            eval "use $mother";
            warn "Could not load $mother: $@"
                if $@;
        
            $mother->import;
        }
        push @$Sub::Mage::Classes, $class;
    }

    {
        no strict 'refs';
        @{"${class}::ISA"} = @$mothers;
    }
}

sub _setup_class {
    my $class = shift;

    *{ "$class\::new" } = sub { return bless { }, $class };
    _import_def ($class, qw/augment accessor/);
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

    if (ref($name) eq 'ARRAY') {
        for my $subname (@$name) {
            $full = "$pkg\:\:$subname";
            my $alter_sub;
            my $new_code;
            my $old_code;
            die "Could not find $subname in the hierarchy for $pkg\n"
                if ! $pkg->can($subname);

            $old_code = \&{$full};
            *$subname = sub {
                $sub->(@_);
                $old_code->(@_);
            };

            _add_to_subs($full);
            *{$full} = \*$subname;
            _debug("Added before hook modifier to $subname");
        }
    }
    else {
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
}

sub around {
    my ($pkg, $name, $sub) = @_;

    if (scalar @_ > 2) {
        ($pkg, $name, $sub) = @_;
    }
    else {
        ($name, $sub) = ($pkg, $name);
        $pkg = caller;
    }

    $full = "$pkg\:\:$name";
    die "Could not find $name in the hierarchy for $pkg\n"
        if ! $pkg->can($name);

    my $old_code = \&{$full};
    *$name = sub {
        $sub->($old_code, @_);
    };
     
    _add_to_subs($full);
    *{$full} = \*$name;  
}

sub getscope {
    my ($self) = @_;

    if (defined $self) { return ref($self); }
    else { return scalar caller(1); }
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

sub duplicate {
    my ($name, %opts) = @_;

    my $from;
    my $to;
    foreach my $opt (keys %opts) {
        $from = $opts{$opt}
            if $opt eq 'from';
        $to = $opts{$opt}
            if $opt eq 'to';
    }

    if ((! $from || ! $to )) {
        warn "duplicate(): 'from' and 'to' needed to cast this spell";
        return ;
    }

    if (! $from->can($name)) {
        warn "duplicate(): $from does not have the method '$name'";
        return ;
    }

    *{$to . "::$name"} = \*{$from . "::$name"};
}
        
sub exports {
    my ($name, %args) = @_;

    my $class = caller;
    my $into = [];
    foreach my $opt (keys %args) {
        if ($opt eq 'into') {
            if (ref($args{into}) eq 'ARRAY') {
                for my $gc (@{$args{into}}) {
                    push @$into, $gc;
                }
            }
            else { push @$into, $args{into}; }
        }
    }
    
    my $code = sub { $class->$name(@_); };
    if (scalar @$into > 0) {
        for my $c (@$into) {
            if (! _class_exists($c)) {
                warn "Can't export $name into $c\:: because class $c does not exist";
                next;
            } 
            *{$c . '::' . $name} = \&{$code};
        }
    }
    return;
}

sub have {
    my ($class, $method, %args) = @_;

    my $can = $class->can($method) ? 1 : 0;
    my $then;
    for $opt (keys %args) {
        if ($opt eq 'then') {
            if ($can) { $args{$opt}->($class, $method); }
        }
        if ($opt eq 'or') {
            if (! $can) {
                if (ref $args{$opt} eq 'CODE') {
                    $args{$opt}->(@_);
                    return 0;
                }
                else { warn $args{$opt}; }
            }
        }
    }
}

sub accessor {
    my ($name, $value) = @_;
    my $pkg = caller;

    *{$pkg . "::$name"} = sub {
        my ($class, $val) = @_;
        if ($val) { *{$pkg . "::$name"} = sub { return $val; }; return $val; }
        else { return $value; }
    };
}

sub _debug_on {
    $Sub::Mage::Debug = 1;
    _debug("Sub::Mage debugging ON");
}

sub _debug {
    print '[debug] ' . shift . "\n"
        if $Sub::Mage::Debug == 1;
}

sub _class_exists {
    my $class = shift;
    
    # i hard a hard time finding out how to go about this
    # this is all i could think of
    # every class should at _least_ have BEGIN, so count the keys!
    my $class = "$class\::";
    return scalar(keys(%{$class}));
}

=head1 IMPORT ATTRIBUTES

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
As of 0.007, C<:Class> now offers B<augmentation> using C<augment> which inherits a specified class, similar to C<use base>

=head1 METHODS 

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

Fancy calling C<before> on multiple subroutines? Sure. Just add them to an array.

    sub like {
        my ($self, $what) = @_;
        
        print "I like $what\n";
    }
    
    sub dislike {
        my ($self, $what) = @_;
        
        print "I dislike $what\n";
    }

    before [qw( like dislike )] => sub {
        my ($self, $name) = @_;

        print "I'm going to like or dislike $name\n";
    };

=head2 around

Around gives the user a bit more control over the subroutine. When you create an around method the first argument will be the old method, the second is C<$self> and the third is any arguments passed to the original subroutine. In a away this allows you to control the flow of the entire subroutine.

    sub greet {
        my ($self, $name) = @_;

        print "Hello, $name!\n";
    }

    # only call greet if any arguments were passed to Class->greet()
    around 'greet' => sub {
        my $method = shift;
        my $self = shift;

        $self->$method(@_)
            if @_;
    };

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

=head2 duplicate

Duplicates a subroutine from one class to another. Probably rarely used, but the feature is there if you need it.

    use ThisPackage;
    use ThatPackage;

    duplicate 'subname' => ( from => 'ThisPackage', to => 'ThatPackage' );

    ThatPackage->subname; # duplicate of ThisPackage->subname

=head2 augment

To use C<augment> you need to have C<:Class> imported. Augment will extend the given class thereby inheriting it into 
the current class.

    package Spell;

    sub lightning { }

    1;

    package Magic;

    use Sub::Mage qw/:Class/;
    augment 'Spell';

    override 'lightning' => sub { say "Zappo!" };
    Magic->lightning;

    1;

The above would not have worked if we had not have augmented 'Spell'. This is because when we 
inheritted it, we also got access to its C<lightning> method.

=head2 exports

Exporting subroutines is not generally needed or a good idea, so Sub::Mage will only allow you to export one subroutine at a time. 
Once you export the subroutine you can call it into the given package without referencing the class of the subroutines package.

    package Foo;
    
    use Sub::Mage;
    
    exports 'boo' => ( into => [qw/ThisClass ThatClass/] );
    export 'spoons' => ( into => 'MyClass' );

    sub spoon { print "Spoons!\n"; }
    sub boo { print "boo!!!\n"; }
    sub test { print "A test\n"; }

    package ThisClass;

    use Foo;

    boo(); # instead of Foo->boo;
    test(); # this will fail because it was not exported

=head2 have

A pretty useless function, but it may be used to silently error, or create custom errors for failed subroutines. Similar to $class->can($method), but with some extra sugar.

    package Foo;

    use Sub::Mage;

    sub test { }
    
    package MyApp;

    use Sub::Mage qw/:5.010/;
    
    use Foo;
    
    my $success = sub {
        my ($class, $name) = @_;
      
        say "$class\::$name checked out OK";  
        after $class => sub {
            say "Successfully ran $name in $class";
        };
    };

    Foo->have( 'test' => ( then => $success ) );

On success the above will run whatever is in C<then>. But what about errors? If this fails it will not do anything - sometimes you just want silent deaths, right? You can create custom 
error handlers by using C<or>. This parameter may take a coderef or a string.

    package Foo;
    
    use Sub::Mage;

    sub knife { }
    
    package MyApp;

    use Sub::Mage qw/:5.010/;

    use Foo;

    my $error = sub {
        my ($class, $name) = @_;

        say "Oh dear! $class failed because no method $name exists";
        # do some other funky stuff if you wish
    };

    Foo->have( 'spoon' => ( then => $success, or => $error ) );

Or you may wish for something really simply.

    Foo->have( 'spoon' => ( then => $success, or => 'There is no spoon') );

This one will simply throw a warning with C<warn> so to still execute any following code you may have.

=head2 accessor

Simply creates an accessor for the current class. You will need to first import C<:Class> when using Sub::Mage before you can use C<accessor>. When you create an 
accessor it adds the subroutine for you with the specified default value. The parameter in the subroutine will cause its default value to change to whatever that is.

    package FooClass;

    use Sub::Mage qw/:Class/;

    accessor 'name' => 'World'; # creates the subroutine 'name'

    1;

    package main;

    use FooClass;

    my $foo = FooClass->new;
    print "Hello, " . $foo->name; # prints Hello, World

    $foo->name('Foo');
    
    print "Seeya, " . $foo->name; # prints Seeya, Foo

=head1 AUTHOR

Brad Haywood <brad@geeksware.net>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
