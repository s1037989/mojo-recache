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

use Mojo::Collection 'c';
use Mojo::ByteStream 'b';
use Mojo::File 'path';
use Mojo::Recache;
use Mojo::URL;
use Mojo::Util 'dumper';

sub cacheable_c { c(pop) }
sub cacheable_b { b(pop) }
sub cacheable_path { path(pop) }
sub cacheable_url { Mojo::URL->new(pop) }
sub cacheable_a { [pop] }
sub cacheable_h { {a => pop} }
sub cacheable_s { \pop }

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
my $ca = $a->cacheable_a(246);
is $a->[0], 246, 'right array value';
is $$a->data->[0], 246, 'right array value';
is $ca->data->[0], 246, 'right array value';

my $h = Mojo::Recache->new();
my $ch = $h->cacheable_h(246);
is $h->{a}, 246, 'right hash value';
is $$h->data->{a}, 246, 'right hash value';
is $ch->data->{a}, 246, 'right hash value';
#NO: diag $$ch;
#is $h->{246}, 246, 'right hash value';

my $s = Mojo::Recache->new();
my $cs = $s->cacheable_s(246);
is ${$$s->data}, 246, 'right scalar value';

my $c = Mojo::Recache->new();
$$c->on(stored => sub { ok shift->cache->name =~ /^[0-9a-f]{32}$/, 'got stored' });
$$c->on(retrieved => sub { ok shift->cache->name =~ /^[0-9a-f]{32}$/, 'got retrieved' });
is $$c->refresh, 'session', 'right refresh';
is ref $$c, 'Mojo::Recache::Backend::Storable', 'right ref';
is $$c->app, 'main', 'right app';
is cacheable_c(246)->first, 246, 'right value';
is $c->cacheable_c(246)->first, 246, 'right value';
my $ct = $c->cacheable_c(246);
is $ct->first, 246, 'right value';
is $c->cacheable_c(247)->data->first, 247, 'right value';
is $c->cacheable_c(248)->cache->data->first, 248, 'right value';
is $c->[0], 248, 'right value';
ok $c =~ /Mojo::Collection/, 'data right class';
is $$c->first, 248, 'right value';
is $$c->data->first, 248, 'right value';
is $$c->cache->data->first, 248, 'right value';
ok $$c->file->isa('Mojo::File'), 'isa Mojo::File';
is ref $$c, 'Mojo::Recache::Backend::Storable', 'right ref';
ok $$c->cache->name =~ /^[0-9a-f]{32}$/, 'got name';
ok !ref $$c->cache->serialize, 'serialized';
is $$c->app, 'main', 'right app';
ok $$c->recachedir->isa('Mojo::File'), 'isa Mojo::File';
my $def = $c->new(refresh => 'daily');
is ref $$def, 'Mojo::Recache::Backend::Storable', 'right ref';
is $$def->refresh, 'daily', 'right refresh';

done_testing;
