package Mojo::Collection::Role::Digits;
use Mojo::Base -role;

sub digits { shift->grep(qr/\d/) }

package App;
use Mojo::Base -base;

use Mojo::Collection;

use Test::More;

sub abc {
  sleep 2;
  diag "NOT CACHED" if $ENV{MOJO_RECACHE_DEBUG};
  return 123;
}

sub def {
  shift;
  sleep 2;
  diag "NOT CACHED" if $ENV{MOJO_RECACHE_DEBUG};
  return Mojo::Collection->with_roles('+Digits')->new(@_);
}

package main;
use 5.010;
use Test::More;

use Mojo::Collection;
use Mojo::File 'path';
use Mojo::Recache;

my $app = App->new;
my $cache = Mojo::Recache->new(app => $app, home => path(__FILE__)->dirname);
$cache->file('.')->dirname->remove_tree;
$cache->on(retrieved => sub { is length(pop), 32, 'emitted right length received name' });
$cache->on(stored => sub { is length(pop), 32, 'emitted right length stored name' });
is $cache->start, undef, 'start disabled due to minion disabled';
is $cache->enqueued, undef, 'enqueued disabled due to minion disabled';
is $cache->enqueue, undef, 'enqueue disabled due to minion disabled';
is $cache->use_options(abc => 123)->options->{abc}, 123, 'right temporary option';
is $cache->options->{abc}, undef, 'temporary option gone';
is $cache->merge_options(abc => 123)->options->{abc}, 123, 'right permanent option';
is $cache->options->{abc}, 123, 'permanent option remained';
my $name = $cache->name(abc => ());
is $name, '56acc414dd5e5902916a1fda50e51fee', 'right name';
is $cache->short($name), '56acc4', 'right short name';
my $file = $cache->file($name);
is $file->basename, '56acc414dd5e5902916a1fda50e51fee', 'right file';
my $t1 = time;
is $app->abc, 123, 'right no cache value';
my $t2 = time;
ok $t2 - $t1 > 1, 'no cache';
is $cache->abc, 123, 'right first cache value';
my $t3 = time;
ok $t3 - $t2 > 1, 'first cache';
is $cache->abc, 123, 'right second cache value';
my $t4 = time;
ok $t4 - $t3 < 1, 'second cache';
my $t5 = time;
is $app->def(1,2,'a',3)->digits->size, 3, 'with_roles: right digits';
my $t6 = time;
ok $t6 - $t5 > 1, 'no cache';
is $cache->def(1,2,'a',3)->digits->size, 3, 'with_roles: right first cache digits';
my $t7 = time;
ok $t7 - $t6 > 1, 'first cache';
is $cache->def(1,2,'a',3)->digits->size, 3, 'with_roles: right second cache digits';
my $t8 = time;
ok $t8 - $t7 < 1, 'second cache';
is $cache->expired($cache->file($cache->name('abc' => ()))), 0, 'not expired';
# test also: cached and extra_args
$cache->file('.')->dirname->remove_tree;

done_testing;
