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
sub cacheable_array { ref $_[0] || $_[0] eq __PACKAGE__ and shift; [@_] }
sub cacheable_hash { ref $_[0] || $_[0] eq __PACKAGE__ and shift; @_%2==0 ? {@_} : {id => @_} }
sub cacheable_scalar { \pop }
sub cacheable_noref { pop }

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
my $cleanup = Mojo::Recache->new;
$$cleanup->recachedir->remove_tree if $$cleanup->recachedir->basename eq 'recache';

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

# Make a new instance and set the refresh to daily
my $daily = $c->new(refresh => 'daily');
isa_ok $$daily, 'Mojo::Recache::Backend::Storable';
is $$daily->refresh, 'daily', 'right refresh';

# All of the above was based on a data set of Mojo::Collection, which is a
# blessed arrayref. Now let's look at other blessed ref types.
# Here, a Mojo::ByteStream.
my $b = Mojo::Recache->new();
my $bcb = $b->cacheable_b("246");
is $b, 246, 'right value';
is $$b->size, 3, 'right size';

my $u = Mojo::Recache->new();
my $ucu = $u->cacheable_url("http://www.mojolicious.org");
# Remember that $u is a Mojo::Recache object, and deref'ing it as the data
# reftype stored in Mojo::Recache::Cache->data returns the data stored in
# Mojo::Recache::Cache.
is $u->{host}, 'www.mojolicious.org', 'right host';
# Remember that $u is a Mojo::Recache object, and deref'ing it as a scalar
# returns the Mojo::Recache::Backend::X object which provides shortcuts to
# the Mojo::Recache::Cache object.
is $$u->scheme, 'http', 'right scheme';
is $$u->data->scheme, 'http', 'right scheme';
is $$u->cache->data->scheme, 'http', 'right scheme';
# Remember that $ucu is the Mojo::Recache::Backend::X object which contains the
# core Mojo::Recache'ing methods as well as the Mojo::Recache::Cache object
# which contains the data, in this case a Mojo::URL object, as well as other
# metadata about the cache.
is $ucu->scheme, 'http', 'right scheme';
is $ucu->data->scheme, 'http', 'right scheme';
is $ucu->cache->data->scheme, 'http', 'right scheme';

# Caveat!
my $s = Mojo::Recache->new();
my $scs = $u->cacheable_scalar("http://www.mojolicious.org");
# Sorry, no overload operators for scalars.  :(
is ${$scs->cache->data}, 'http://www.mojolicious.org', 'right scalar data';
# Otherwise still normal.
is $$s->refresh, 'session', 'right refresh attribute value';
TODO: {
  local $TODO = 'Is there any way to overload the scalar operator?';
  eval { return $s };
  ok $@;
};

# Aside from the caveat, all works as expected
# functions / methods that return arrays...
my $a = Mojo::Recache->new();
my $aca = $a->cacheable_array(246);
is $a->[0], 246, 'right array value';
is $$a->data->[0], 246, 'right array value';
is $aca->data->[0], 246, 'right array value';

# functions / methods that return hashes...
my $h = Mojo::Recache->new();
my $hch = $h->cacheable_hash(246);
is $h->{id}, 246, 'right hash value';
is $$h->data->{id}, 246, 'right hash value';
is $hch->data->{id}, 246, 'right hash value';
# There's no methods to call on data because data isn't an object.
# But we can still inspect the metadata:
is $hch->cache->method, 'cacheable_hash', 'right metadata value';

# functions / methods that return strings...
my $n = Mojo::Recache->new();
my $ncn = $n->cacheable_noref("http://www.mojolicious.org");
# Here, it's a string operator overload, and it works well like normal.
is $n, 'http://www.mojolicious.org', 'right non-ref string data';
# Otherwise still normal.
isa_ok $n, 'Mojo::Recache';
isa_ok $$n, 'Mojo::Recache::Backend::Storable';
is $$n->refresh, 'session', 'right refresh attribute value';
isa_ok $ncn, 'Mojo::Recache::Backend::Storable';
is $ncn->refresh, 'session', 'right refresh attribute value';

# Likely the most common usage for Mojo::Recache is using it within another
# module. You'll be able to use the module 100% like normal, but you'll
# also be able to cache methods of the module by accessing it via the
# Mojo::Recache instance, keeping access to the module method's data as
# native and expected as possible.
my $ss = Mojo::SomeService->new;
# First, the obligatory non-cache interface for a control:
is $ss->cacheable_thing(579)->first, 579, 'right value';
# Ok, let's cache that method now!
my $rct = $ss->recache->cacheable_thing(579);
# Here's a cool feature: because you'rew calling the object method thru the
# cache interface, the object method has the ability to know that it is
# wanting to be cached and therefore it can behave differently.
# Notice we passed 579, but the response, according to the method, is 580!
is $ss->recache->[0], 580, 'caching';
# Again, normal access mechanisms...
is ${$ss->recache}->refresh, 'session', 'right refresh';
isa_ok ${$ss->recache}->app, 'Mojo::SomeService';
is $rct->refresh, 'session', 'right refresh';
isa_ok $rct->app, 'Mojo::SomeService';
is $rct->first, 580, 'caching...';
# But this is great: thru the Mojo::Recache::Cache object, you have the ability
# to know if you are dealing with cached data or not.
# In this case, first access, the data that you're dealing with is _not_ from
# a cache.
is $rct->cache->cached, 0, 'not cached';
# But call the method and arguments exactly again, and this time you can see
# that you are dealing with _cached_ data!
is $ss->recache->cacheable_thing(579)->cache->cached, 1, 'cached';

# And, finally, maybe you want everything you do on this class instance to be
# cached. You can do that, too:
my $ss1 = Mojo::SomeService->new;
is ${$ss1->recache}->refresh, 'session', 'right refresh';
isa_ok ${$ss1->recache}->app, 'Mojo::SomeService';
isa_ok $ss1->recache->cacheable_thing(579), 'Mojo::Recache::Backend::Storable';
$ss1 = $ss1->recache;
is $ss1->[0], 580, 'right first caching value';
isa_ok $$ss1, 'Mojo::Recache::Backend::Storable';
is $$ss1->first, 580, 'right first caching value';
isa_ok $ss1->cacheable_thing(579), 'Mojo::Recache::Backend::Storable';
is $ss1->[0], 580, 'right first caching value';
isa_ok $$ss1, 'Mojo::Recache::Backend::Storable';
is $$ss1->first, 580, 'right first caching value';
#isa_ok $ss1->app, 'Mojo::SomeService'; # because of weaken!
my $ss1ct = $ss1->cacheable_thing(579);
is $ss1ct->data->[0], 580, 'right first caching value';
is $ss1ct->first, 580, 'right first caching value';
isa_ok $ss1ct->data, 'Mojo::Collection';

# This is probably what you want
# There is no access to the weakened app attribute in Mojo::Recache::Backend
my $mssr = Mojo::SomeService->new->recache;
my $mssrct = $mssr->cacheable_thing(579);
isa_ok $$mssr, 'Mojo::Recache::Backend::Storable';
ok !$mssr->_recachedir, 'no response expected';
is $mssr->[0], 580, 'right first caching value';
is $$mssr->first, 580, 'right first caching value';
is $$mssr->cache->data->first, 580, 'right first caching value';
is $$mssr->cache->data->[0], 580, 'right first caching value';
is $mssrct->first, 580, 'right first caching value';
is $mssrct->cache->data->first, 580, 'right first caching value';
is $mssrct->cache->data->[0], 580, 'right first caching value';
is $mssrct->refresh, 'session', 'right refresh';
is $mssrct->delay, 60, 'right delay';
is $mssrct->cache->method, 'cacheable_thing', 'right method';
is $mssrct->cache->args->[0], 579, 'right first arg';

###########################################################################################
$$cleanup->recachedir->remove_tree if $$cleanup->recachedir->basename eq 'recache';
done_testing;
