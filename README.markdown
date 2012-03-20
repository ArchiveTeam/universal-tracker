A configurable tracker with dashboard.  [![Build Status](https://secure.travis-ci.org/ArchiveTeam/universal-tracker.png)](http://travis-ci.org/ArchiveTeam/universal-tracker)

Can run on Heroku, with a Redis server somewhere.

Needs documentation.

Terminology
===========

- `items`: users, members or another type of unit that is to be saved. Each item is identified by a unique string, e.g., the username.
- `domains`: identify parts of an item (e.g., mobileme is is divided in web, gallery, public.me.com and homepage.mac.com). This is only used for statistics.


Basics / Redis structure
========================

1. The new items are added to the `todo` set.
2. When a downloader requests an item, the tracker removes a random item from the `todo` set and adds it to the `out` zset and the `claims` hash.
3. When a downloader completes an item, the tracker removes the item from `out` and `claims` and adds it to the `done` set. The statistics about the item are appended to the `log` list.

The main Redis structures used by this process:

- `todo`: a set with the unclaimed items.
- `out`: a zset with the claimed items, with for each item the time when it was claimed.
- `claims`: a hash with the downloader name and ip for every claimed item.
- `done`: a set with the items that have been completed.
- `log`: a list of JSON objects, with details of each completed item.

The tracker checks more than one `todo` queue. It will return the item from the first queue in this order:

1. It checks the downloader-specific queue `todo:d:#{ downloader }`.
2. Then it checks the general queue `todo`.
3. The lower-priority queue `todo:secondary`.
4. The redo queue `todo:redo` (this isn't actually used; the idea was to assign released claims to another user).

If no item is found in any of these queues, the tracker returns a 404 Not Found response.

The tracker maintains several statistics to feed the dashboard:

- `downloader_count`: a hash (downloader -> item count) indicating the number of downloaded items per downloader.
- `downloader_bytes`: a hash (downloader -> total bytes) indicating the downloaded bytes per downloader.
- `downloader_version`: a hash (downloader -> script version) with the version number reported by the downloader.
- `downloader_chartdata:#{ downloader }`: a list of [timestamp,bytes] pairs, logging the growth of `downloader_bytes` over time.
- `items_done_chartdata`: a list of [timestamp,item count] pairs, logging the progress over time.
- `domain_bytes`: a hash (domain -> total bytes) with the total number of bytes for each domain.

Rate-limiting is implemented as follows:

1. The tracker counts the number of items given out in this minute by incrementing `requests_processed:#{ minute }`.
2. If `requests_per_minute` is set and `requests_per_minute` < `requests_processed:#{ minute }`, no new items will be given out until the next minute begins.

(This may not be ideal, since it can generate a large burst of activity in the first seconds of a minute and then nothing.)

Downloaders can be blocked by adding the IP address to `blocked`. Blocked downloaders will not receive a username. Downloaders that send invalid requests will be blocked automatically.


HTTP API
========

The clients communicate with the tracker over HTTP. Payloads are in JSON format, so the client should add a "Content-Type: application/json" header.

Requesting a new item:

  POST /request
  {"downloader":"#{ downloader_name }"}

The tracker will respond with the name of the next item:

  #{ item_name }

Response 404 with an empty body indicates that no item is available. The client should wait for a while and try again. Similarly, response 420 with an empty body indicates that the rate limiting is active. The client should wait for a while and try again.

Completing an item:

  POST /done
  {"downloader":"#{ downloader_name }","item":"#{ item_name }","bytes":{"#{ domain_a }":#{ bytes_a },"#{ domain_b }":#{ bytes_b }},"version":#{ script_version }","id":"#{ checksum }"}

The `bytes` field contains an entry with the number of bytes for each domain of the item. The `id` field can contain an arbitrary checksum; this value is stored in the log and can be used to check results.

The tracker responds with HTTP status 200 and a body of two characters:

  OK

If the tracker does not respond with 200 / OK, the client should wait for a little while and send the request again.

