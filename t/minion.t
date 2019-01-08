use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

use Mojo::File 'path';
use Mojo::Recache;
use Mojo::Util 'dumper';

# Isolate tests
require Mojo::Pg;
my $pg = Mojo::Pg->new($ENV{TEST_ONLINE});
$pg->db->query('drop schema if exists minion_test cascade');
$pg->db->query('create schema minion_test');
require Minion;
my $minion = Minion->new(Pg => $ENV{TEST_ONLINE})->app(__PACKAGE__);
my $cache = Mojo::Recache->new(app => __PACKAGE__, home => path(__FILE__)->dirname, minion => $minion);
$minion = $cache->minion;
$pg = $minion->backend->pg;
$minion->backend->pg->search_path(['minion_test']);
$cache->file('fd4f16df902fda892dadf2dd1bf40742')->remove;

# Nothing to repair
my $worker = $minion->repair->worker;
isa_ok $worker->minion->app, __PACKAGE__, 'has specified application';

# Queue up minion jobs, but don't duplicate unfinished jobs
$cache->on(enqueued => sub { ok pop, 'emitted enqueued job' });
ok !$cache->enqueued('fd4f16df902fda892dadf2dd1bf40742'), 'not enqueued';
is $cache->abc, 123, 'right first cache value';
is $cache->enqueued('fd4f16df902fda892dadf2dd1bf40742'), 1, 'enqueued';
is $cache->abc, 123, 'right second cache value';
is $cache->enqueued('fd4f16df902fda892dadf2dd1bf40742'), 1, 'not enqueued twice';

# HIGH: Write tests for:
#       - cron support (monthly, daily)
#       - cron job foreground worker
#       - non-cron background worker

# Clean up once we are done
$pg->db->query('drop schema minion_test cascade');
$cache->file('fd4f16df902fda892dadf2dd1bf40742')->remove;

sub abc {
  sleep 2;
  return 123
}

done_testing;
