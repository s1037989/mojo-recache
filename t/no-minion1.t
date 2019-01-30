package Mojo::SomeService;
use Mojo::Base -base;

use Mojo::Collection 'c';
use Mojo::Recache;

has cached  => 0;
has recache => sub { Mojo::Recache->new(app => shift) };

sub cacheable_thing {
  my ($self, $value) = (shift, shift);
  c($self->cached ? $value + 1 : $value);
}

package main;
use Test::More;

use Mojo::ByteStream 'b';
use Mojo::Collection 'c';
use Mojo::File 'path';
use Mojo::Recache;
use Mojo::URL;
use Mojo::Util 'dumper';

sub cacheable_b { b(pop) }
sub cacheable_c { ref $_[0] || $_[0] eq __PACKAGE__ and shift; c(@_) }
sub cacheable_path { path(pop) }
sub cacheable_url { Mojo::URL->new(pop) }
sub cacheable_array { ref $_[0] and shift; [@_] }
sub cacheable_hash { ref $_[0] and shift; @_%2==0 ? {@_} : {id => @_} }
sub cacheable_scalar { \pop }

# Full testing of all features on a main::sub() with an array-based collection
# return value. This is the most purest form. It may not be the most common
# usage tho.
# First a test of a non-caching direct call.
is cacheable_c(246,290)->last, 290, 'right last value';

# Ok, time to move on to setting up for caching that function above.
# Mojo::Recache returns an object in which a Mojo::Recache::Backend::X instance
# (Storable by default) is now now an object in the Mojo::Recache package.
# This has an interesting effect. It allows access to the Mojo::Recache instance
# via the return value, and allows access to the Mojo::Recache::Backend::X
# instance via the reference to that return value.
my $c = Mojo::Recache->new();
isa_ok $c, 'Mojo::Recache';
isa_ok $$c, 'Mojo::Recache::Backend::Storable';

# By design, there aren't many methods available in this package because we want
# to maximize AUTOLOAD's capability to call methods in the specified app.
# _recachedir is a *function* in the Mojo::Recache package. As you can see, we
# can call this function via the reference to the Mojo::Recache instance stored
# in $c.
ok !$c->_recachedir, 'truly a private function';

# Ok, time to move on to the more interesting capability of
# Mojo::Recache::Backend::X. We access these methods by dereferencing the
# Mojo::Recache instance.
isa_ok $$c->recachedir, 'Mojo::File';
is $$c->recachedir->basename, 'recache', 'right default cachedir name';
is $$c->refresh, 'session', 'right default refresh';
is $$c->app, __PACKAGE__, 'right app package';
eval { $$c->cache };
ok $@, 'no cache defined yet';

# Keep the recache repo clear for these tests
$$c->recachedir->remove_tree if $$c->recachedir->basename eq 'recache';

# Mojo::Recache is a subclass of Mojo::EventEmitter and therefore emits some
# events. The most common are stored and retrieved.
# These won't do anything until stored or retrieved are called and are given
# the opportunity to emit the respective event.
$$c->on(stored => sub { ok shift->cache->name =~ /^[0-9a-f]{32}$/, 'got stored event with cache object for detail inspection' });
$$c->on(retrieved => sub { ok shift->cache->name =~ /^[0-9a-f]{32}$/, 'got retrieved event with cache object for detail inspection' });

# Time to start caching things.
# The Mojo::Recache instance is pretty much good for one thing:
#   Calling the function in the app package and wrapping it in a caching
#   mechanism.
# This is the most common way to use Mojo::Recache:
#   From the Mojo::Recache object, call the function in the app package
#   Mojo::Recache AUTOLOAD will call the function from the app and cache the
#   return value. If it's already cached, it'll simply return the cached
#   value and not bother calling the function from the app.
# This is all you really need; but there's a lot of cool functionality left to
# explore...  Stick around!
is $c->cacheable_c(246, 290)->last, 290, 'right last value; stored event should have just occurred';
# From the dereferenced form which is a Mojo::Recache::Backend::X object, you
# can access all kinds of interesting methods and attributes.
# We can get direct access to the data, and the data can even be an object
# itself.
is $$c->cache->data->last, 290, 'same right last value';
# But wait, there's more! You can find out if the data is cached data or fresh.
# We had a clear cache up to this point, so our first (and only) call to this
# point is _not_ cached.
is $$c->cache->cached, 0, 'return value of the previous test was cachable, but not yet cached';
# What happens when we access the exact same function and arguments again...
is $c->cacheable_c(246, 290)->last, 290, 'right last value; cacheable and cached (but non-object function cannot know that); retrieved event should have just occurred';
# This time the data is cached! It got the data from the cache store instead of
# doing a fresh call to the typically slow app function.
is $$c->cache->cached, 1, 'return value of the previous test was cachable, this time it pulled from cache';
# And, of course, we still have access to the same data in the same way.
is $$c->cache->data->last, 290, 'same right last value';
# But what if we call the function again, but with different arguments?
# Still get the data you expect!
is $c->cacheable_c(642, 92)->last, 92, 'right last value';
# But since it's a new call with new arguments, it's not cached!
is $$c->cache->cached, 0, 'not cached';
# Access it again...
is $c->cacheable_c(642, 92)->last, 92, 'right last value';
# And this time it's cached!
is $$c->cache->cached, 1, 'cached';
# Ok, let's try that first call again:
is $c->cacheable_c(246, 290)->last, 290, 'right last value';
# It's still cached!
is $$c->cache->cached, 1, 'cached';
# And the data is still what we expect!
is $$c->cache->data->last, 290, 'same right last value';

# Here's a quick fun fact:
# Mojo::Recache's overloaded operators lets us access the data for the cached
# function super conveniently!
is $c->[1], 290, 'same right last value';
# Or get all the data like a normal data structure!
is join('',@$c), 246290, 'all the right data';
# Look, the data is really what you'd expect!
ok $c =~ /Mojo::Collection/, 'data is the right package';

# Now let's call our app function and store it in a variable.
my $ccc = $c->cacheable_c(246, 290);
# Multiple accesses to the data are now more convenient.
# The variable contains just the data as you'd expect.
# These methods are available via AUTOLOAD, so there are some reserved keywords
# that you will not be able to use this method for. Don't worry, there's more
# direct methods, this is just a convenience shortcut.
# Reserved Keywords are all the documented attributes and methods.
is $ccc->first, 246, 'right first value';
is $ccc->last,  290, 'right last  value';
# We can also access the data the long and boring way.
is $ccc->data->first, 246, 'right first value';
# But data itself is just a shortcut to the true direct method:
is $ccc->cache->data->last,  290, 'right last value';
# And, as already shown, you don't have to go thru the stored vairable; use the
# original Mojo::Recache instance!
is $$c->cache->data->last,  290, 'right last value';

# Let's talk briefly about some of those Reverse Keywords. What else can the
# cached instance do?
# Well, we can see where the cached file is stored!
ok $$c->file->isa('Mojo::File'), 'isa Mojo::File';
# Trust me on this one.
ok $$c->file->basename =~ /^[0-9a-f]{32}$/, 'looks like';
# And what's the name of the cache instance?
is $$c->cache->name, '22538e095fe195f5052a634610d1b4a4', 'right cache name';
# Is it expired?
ok !$$c->expired, 'not expired';
# Expire it (which is just an alias for remove, removing the cache file)
$$c->expire;
# The data is still in memory tho.
is $$c->cache->data->last,  290, 'right last value';
ok $$c->cache->cached, 'cached';
# But another call to the same function and arguments will re-fetch it.
is $c->cacheable_c(246, 290)->last, 290, 'right last value';
ok !$$c->cache->cached, 'not cached';

# Notable mention:
# Inspect how we serialized the call to the app function, this is key component
# behind Mojo::Recache. Each unique call to an app function *and* the arguments
# is a new cache file.
ok !ref $$c->cache->serialize, 'serialized';
# Here's the unique serialization of the last app function call:
is $$c->cache->serialize, '["cacheable_c",[246,290],[]]', 'correct serialization';

###################
# Ok, that was the in-depth overview of all of the functionality.
# Now we return to simply testing the variations on it all.

###########################################################################################
$$c->recachedir->remove_tree if $$c->recachedir->basename eq 'recache'; done_testing; exit;

my $def = $c->new(refresh => 'daily');
is ref $$def, 'Mojo::Recache::Backend::Storable', 'right ref';
is $$def->refresh, 'daily', 'right refresh';

my $b = Mojo::Recache->new();
my $cb = $b->cacheable_b("246");
is $b, 246, 'right value';
is $$b->size, 3, 'right size';

my $u = Mojo::Recache->new();
my $cu = $u->cacheable_url("http://www.mojolicious.org");
is $cu->scheme, 'http', 'right scheme';
is $u->{host}, 'www.mojolicious.org', 'right host';
#is $b, 246, 'right value';
#is $$b->size, 3, 'right size';

my $a = Mojo::Recache->new();
my $ca = $a->cacheable_array(246);
is $a->[0], 246, 'right array value';
is $$a->data->[0], 246, 'right array value';
is $ca->data->[0], 246, 'right array value';

my $h = Mojo::Recache->new();
my $ch = $h->cacheable_hash(246);
is $h->{a}, 246, 'right hash value';
is $$h->data->{a}, 246, 'right hash value';
is $ch->data->{a}, 246, 'right hash value';
#NO: diag $$ch;
#is $h->{246}, 246, 'right hash value';

my $s = Mojo::Recache->new();
my $cs = $s->cacheable_scalar(246);
is ${$$s->data}, 246, 'right scalar value';

my $ss = Mojo::SomeService->new;
is $ss->cacheable_thing(579)->first, 579, 'right value';
my $rct = $ss->recache->cacheable_thing(579);
is $ss->recache->[0], 580, 'caching';
is ${$ss->recache}->refresh, 'session', 'right refresh';
is $rct->first, 580, 'caching...';
is $rct->cache->cached, 0, 'not cached';
is $ss->recache->cacheable_thing(579)->cache->cached, 1, 'cached';

my $ss1 = Mojo::SomeService->new->recache;
is $$ss1->refresh, 'session', 'right refresh';
my $ss1ct = $ss1->cacheable_thing(579);
is $ss1->[0], 580, 'correctly cached';
is $ss1ct->data->[0], 580, 'right value';
is $ss1ct->first, 580, 'right value';
#is $ss1->cacheable_thing(580)->first, 580, 'right value';
#my $rct = $ss->recache->cacheable_thing(579);
#is $ss->recache->[0], 580, 'caching';
#diag ${$ss->recache}->refresh;
#is $rct->first, 580, 'caching...';
#is $rct->cache->cached, 0, 'not cached';
#is $ss->recache->cacheable_thing(579)->cache->cached, 1, 'cached';

done_testing;
