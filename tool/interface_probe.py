#!/usr/bin/env python3
"""Dependency-free smoke probes for the public endpoints used by Pure Live."""

from __future__ import annotations

import json
import hashlib
import gzip
import html
import re
import secrets
import sys
import time
import http.cookiejar
import urllib.parse
import urllib.request

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(errors="replace")

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
)


def request_json(url: str, params: dict[str, object] | None = None, attempts: int = 3) -> object:
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    origin = urllib.parse.urlsplit(url)
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            # Rebuild the request for every retry. Some CDNs close or rate-limit a
            # keep-alive connection after an empty/HTML challenge response.
            request = urllib.request.Request(
                url,
                headers={
                    "User-Agent": USER_AGENT,
                    "Referer": f"{origin.scheme}://{origin.netloc}/",
                    "Accept": "application/json,text/plain,*/*",
                    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
                    "Cache-Control": "no-cache",
                    "Connection": "close",
                },
            )
            with urllib.request.urlopen(request, timeout=20) as response:
                raw_payload = response.read()
                # A few platform CDNs return gzip even when the client did not
                # advertise compression. urllib deliberately leaves it intact.
                if (
                    response.headers.get("Content-Encoding", "").lower() == "gzip"
                    or raw_payload.startswith(b"\x1f\x8b")
                ):
                    raw_payload = gzip.decompress(raw_payload)
                payload = raw_payload.decode("utf-8", errors="replace")
            if not payload.strip():
                raise ValueError("empty response body")
            try:
                return json.loads(payload.lstrip("\ufeff"))
            except json.JSONDecodeError as error:
                content_type = response.headers.get("Content-Type", "unknown")
                preview = payload[:80].replace("\r", " ").replace("\n", " ")
                raise ValueError(f"non-JSON response ({content_type}): {preview!r}") from error
        except Exception as error:  # noqa: BLE001 - preserve endpoint diagnostics
            last_error = error
            if attempt < attempts:
                time.sleep(attempt)
    assert last_error is not None
    raise last_error


def post_json(
    url: str,
    payload: object,
    headers: dict[str, str] | None = None,
    attempts: int = 3,
) -> object:
    """POST JSON with bounded retries and preserve response diagnostics."""
    body = json.dumps(payload, separators=(",", ":")).encode()
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            request = urllib.request.Request(
                url,
                data=body,
                method="POST",
                headers={
                    "User-Agent": USER_AGENT,
                    "Accept": "application/json",
                    "Content-Type": "text/plain; charset=UTF-8",
                    # Platform CDNs occasionally tear down pooled TLS sockets
                    # with an EOF on this Windows host. Each bounded retry gets
                    # an independent connection, matching request_json.
                    "Connection": "close",
                    **(headers or {}),
                },
            )
            with urllib.request.urlopen(request, timeout=20) as response:
                raw_payload = response.read()
            if not raw_payload.strip():
                raise ValueError("empty response body")
            return json.loads(raw_payload.decode("utf-8", errors="replace").lstrip("\ufeff"))
        except Exception as error:  # noqa: BLE001 - preserve endpoint diagnostics
            last_error = error
            if attempt < attempts:
                time.sleep(attempt)
    assert last_error is not None
    raise last_error


def post_form_json(
    url: str,
    payload: dict[str, object],
    params: dict[str, object] | None = None,
    attempts: int = 3,
    headers: dict[str, str] | None = None,
) -> object:
    """POST form data with bounded retries for platform player endpoints."""
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    body = urllib.parse.urlencode(payload).encode()
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            request = urllib.request.Request(
                url,
                data=body,
                method="POST",
                headers={
                    "User-Agent": USER_AGENT,
                    "Accept": "application/json,text/plain,*/*",
                    "Content-Type": "application/x-www-form-urlencoded",
                    **(headers or {}),
                },
            )
            with urllib.request.urlopen(request, timeout=20) as response:
                raw_payload = response.read()
            if not raw_payload.strip():
                raise ValueError("empty response body")
            return json.loads(raw_payload.decode("utf-8", errors="replace").lstrip("\ufeff"))
        except Exception as error:  # noqa: BLE001 - preserve endpoint diagnostics
            last_error = error
            if attempt < attempts:
                time.sleep(attempt)
    assert last_error is not None
    raise last_error


def require_path(value: object, *path: str) -> object:
    current = value
    for part in path:
        if not isinstance(current, dict) or part not in current:
            raise ValueError(f"missing JSON path: {'.'.join(path)}")
        current = current[part]
    return current


def douyu_encryption_probe() -> None:
    """Validate the current pure-Dart signing descriptor and its time unit."""
    payload = request_json(
        "https://www.douyu.com/wgapi/livenc/liveweb/websec/getEncryption",
        {"did": "10000000000000000000000000001501"},
    )
    data = payload.get("data") if isinstance(payload, dict) else None
    if not isinstance(data, dict):
        raise ValueError("Douyu encryption payload is missing data")
    for key in ("key", "rand_str", "enc_data"):
        if not str(data.get(key, "")).strip():
            raise ValueError(f"Douyu encryption payload is missing {key}")
    enc_time = int(data.get("enc_time", 0))
    expire_at = int(data.get("expire_at", 0))
    if not 1 <= enc_time <= 16:
        raise ValueError("Douyu encryption iteration count is out of bounds")
    if expire_at <= int(time.time()):
        raise ValueError("Douyu encryption descriptor is already expired")


def douyu_playback_probe(room_ids: list[str] | None = None) -> None:
    """Exercise signing, H5 metadata, CDN URL and the actual FLV header."""
    did = secrets.token_hex(16)
    descriptor_payload = request_json(
        "https://www.douyu.com/wgapi/livenc/liveweb/websec/getEncryption",
        {"did": did},
    )
    descriptor = descriptor_payload.get("data") if isinstance(descriptor_payload, dict) else None
    if not isinstance(descriptor, dict):
        raise ValueError("Douyu encryption payload is missing data")

    if room_ids is None:
        recommendation = request_json("https://www.douyu.com/japi/weblist/apinc/allpage/6/1")
        rooms = recommendation.get("data", {}).get("rl", []) if isinstance(recommendation, dict) else []
        if not isinstance(rooms, list) or not rooms:
            raise ValueError("Douyu recommendation returned no rooms")
        candidate_ids = [str(room.get("rid", "")).strip() for room in rooms[:10] if isinstance(room, dict)]
    else:
        candidate_ids = [str(room_id).strip() for room_id in room_ids]

    errors: list[str] = []
    for room_id in candidate_ids:
        if not room_id:
            continue
        try:
            timestamp = int(time.time())
            key = str(descriptor["key"])
            secret = str(descriptor["rand_str"])
            iterations = int(descriptor["enc_time"])
            for _ in range(iterations):
                secret = hashlib.md5(f"{secret}{key}".encode()).hexdigest()
            salt = "" if int(descriptor.get("is_special", 0)) == 1 else f"{room_id}{timestamp}"
            auth = hashlib.md5(f"{secret}{key}{salt}".encode()).hexdigest()
            form = {
                "enc_data": descriptor["enc_data"],
                "tt": timestamp,
                "did": did,
                "auth": auth,
                "cdn": "",
                "rate": -1,
                "hevc": 0,
                "fa": 0,
                "ive": 0,
                "ver": "Douyu_new",
                "iar": 0,
            }
            headers = {
                "Origin": "https://www.douyu.com",
                "Referer": f"https://www.douyu.com/{room_id}",
                "Cookie": f"dy_did={did}; acf_did={did}",
            }
            response = post_form_json(
                f"https://www.douyu.com/lapi/live/getH5PlayV1/{room_id}",
                form,
                attempts=2,
                headers=headers,
            )
            if not isinstance(response, dict) or int(response.get("error", -1)) != 0:
                raise ValueError(f"H5 error={response.get('error') if isinstance(response, dict) else 'invalid'}")
            data = response.get("data")
            if not isinstance(data, dict):
                raise ValueError("H5 playback data missing")
            rates = data.get("multirates")
            cdns = data.get("cdnsWithName")
            if not isinstance(rates, list) or not rates:
                raise ValueError("H5 quality list missing")
            if not isinstance(cdns, list) or not cdns:
                raise ValueError("H5 CDN list missing")
            base = str(data.get("rtmp_url", "")).rstrip("/")
            live = html.unescape(str(data.get("rtmp_live", ""))).lstrip("/")
            stream_url = live if live.startswith(("http://", "https://")) else f"{base}/{live}"
            if not stream_url.startswith(("http://", "https://")):
                raise ValueError("H5 stream URL missing")
            stream_request = urllib.request.Request(
                stream_url,
                headers={
                    "User-Agent": USER_AGENT,
                    "Origin": "https://www.douyu.com",
                    "Referer": f"https://www.douyu.com/{room_id}",
                    "Cookie": f"dy_did={did}; acf_did={did}",
                    "Range": "bytes=0-31",
                    "Connection": "close",
                },
            )
            with urllib.request.urlopen(stream_request, timeout=20) as stream_response:
                prefix = stream_response.read(16)
            if not prefix.startswith(b"FLV"):
                raise ValueError(f"CDN returned a non-FLV prefix: {prefix[:8]!r}")
            return
        except Exception as error:  # noqa: BLE001 - try another active room
            errors.append(f"{room_id}: {error}")
    raise ValueError("; ".join(errors[-3:]) or "no usable Douyu room")


def douyu_reported_room_probe() -> None:
    """Recheck the concrete room reported by upstream issue #799."""
    room_id = "71415"
    payload = request_json(f"https://www.douyu.com/betard/{room_id}")
    room = payload.get("room") if isinstance(payload, dict) else None
    if not isinstance(room, dict) or str(room.get("room_id", "")) != room_id:
        raise ValueError("reported Douyu room metadata is missing")
    if int(room.get("show_status", 0)) != 1 or int(room.get("videoLoop", 0)) == 1:
        return
    douyu_playback_probe([room_id])


def douyu_search_probe() -> None:
    """Validate the anonymous search contract without relying on one keyword."""
    errors: list[str] = []
    for keyword in ("ASMR", "", "英雄联盟"):
        try:
            response = request_json(
                "https://www.douyu.com/japi/search/api/searchShow",
                {"kw": keyword, "page": 1, "pageSize": 20},
            )
            data = response.get("data") if isinstance(response, dict) and response.get("error") == 0 else None
            if isinstance(data, dict) and isinstance(data.get("relateShow"), list):
                return
            errors.append(f"{keyword or '<empty>'}: invalid response shape")
        except Exception as error:  # noqa: BLE001 - verify bounded query variants
            errors.append(f"{keyword or '<empty>'}: {error}")
    raise ValueError("; ".join(errors))


_yy_room_cache: dict[str, object] | None = None








def kuaishou_playback_probe() -> None:
    """Validate the current live/replay list shape and room-page status."""
    payload = request_json("https://live.kuaishou.com/live_api/home/list")
    if not isinstance(payload, dict):
        raise ValueError("Kuaishou home payload is not an object")
    groups = payload.get("data", {}).get("list", [])
    candidates: list[dict[str, object]] = []
    for group in groups if isinstance(groups, list) else []:
        for game in group.get("gameLiveInfo", []) if isinstance(group, dict) else []:
            for item in game.get("liveInfo", []) if isinstance(game, dict) else []:
                if isinstance(item, dict):
                    candidates.append(item)
    if not candidates:
        raise ValueError("Kuaishou home list has no room cards")

    selected: dict[str, object] | None = None
    for item in candidates:
        play_urls = item.get("playUrls")
        descriptors = play_urls if isinstance(play_urls, list) else [play_urls]
        for descriptor in descriptors:
            if not isinstance(descriptor, dict):
                continue
            adaptation = descriptor.get("adaptationSet")
            representations = adaptation.get("representation") if isinstance(adaptation, dict) else None
            if isinstance(representations, list) and any(
                isinstance(rep, dict) and str(rep.get("url", "")).startswith(("http://", "https://"))
                for rep in representations
            ):
                selected = item
                break
        if selected is not None:
            break
    if selected is None:
        raise ValueError("Kuaishou list has no playable live/replay descriptor")

    author = selected.get("author")
    room_id = str(author.get("id", "")) if isinstance(author, dict) else ""
    if not room_id:
        raise ValueError("Kuaishou playback card is missing author id")
    request = urllib.request.Request(
        f"https://live.kuaishou.com/u/{urllib.parse.quote(room_id)}",
        headers={"User-Agent": USER_AGENT, "Connection": "close"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        html = response.read().decode("utf-8", errors="replace")
    match = re.search(r"window\.__INITIAL_STATE__=(.*?);", html)
    if match is None:
        raise ValueError("Kuaishou room initial state marker is missing")
    state = json.loads(match.group(1).replace("undefined", "null"))
    rooms = state.get("liveroom", {}).get("playList", []) if isinstance(state, dict) else []
    if (
        not isinstance(rooms, list)
        or not rooms
        or not isinstance(rooms[0], dict)
        or not isinstance(rooms[0].get("isLiving"), bool)
    ):
        raise ValueError("Kuaishou room status is missing")


def douyin_search_probe() -> None:
    """Exercise the anonymous partition fallback used when live search asks for login."""
    cookie_jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookie_jar))

    def get_json(url: str, params: dict[str, object], attempts: int = 3) -> object:
        last_error: Exception | None = None
        for attempt in range(1, attempts + 1):
            try:
                request = urllib.request.Request(
                    f"{url}?{urllib.parse.urlencode(params)}",
                    headers={
                        "User-Agent": USER_AGENT,
                        "Accept": "application/json,text/plain,*/*",
                        "Accept-Language": "zh-CN,zh;q=0.9",
                        "Referer": "https://live.douyin.com/",
                        "Cache-Control": "no-cache",
                        "Connection": "close",
                    },
                )
                with opener.open(request, timeout=20) as response:
                    payload = response.read()
                if not payload.strip():
                    raise ValueError("empty response body")
                return json.loads(payload.decode("utf-8", errors="replace").lstrip("\ufeff"))
            except Exception as error:  # noqa: BLE001 - bounded transient retry
                last_error = error
                if attempt < attempts:
                    time.sleep(attempt)
        assert last_error is not None
        raise last_error

    last_home_error: Exception | None = None
    for attempt in range(1, 4):
        try:
            home_request = urllib.request.Request(
                "https://live.douyin.com/?from_nav=1",
                headers={"User-Agent": USER_AGENT, "Cache-Control": "no-cache", "Connection": "close"},
            )
            with opener.open(home_request, timeout=20) as response:
                # Drain the bootstrap response before reusing its anonymous
                # cookies. With urllib, closing it after one byte consistently
                # made the immediately following feed return HTTP 503; fully
                # consuming the same response produces a healthy feed request.
                response.read()
            break
        except Exception as error:  # noqa: BLE001 - bounded transient retry
            last_home_error = error
            if attempt < 3:
                time.sleep(attempt)
    else:
        assert last_home_error is not None
        raise last_home_error
    if not any(cookie.name == "ttwid" for cookie in cookie_jar):
        raise ValueError("anonymous ttwid cookie missing")

    search = get_json(
        "https://live.douyin.com/webcast/web/partition/search/",
        {"keyword": "三角洲", "aid": 6383},
    )
    require_path(search, "data", "SearchResult")
    partitions = search["data"]["SearchResult"]  # type: ignore[index]
    if not isinstance(partitions, list) or not partitions:
        raise ValueError("partition search returned no matching category")
    partition = partitions[0].get("partition") if isinstance(partitions[0], dict) else None
    if not isinstance(partition, dict) or not partition.get("id_str") or partition.get("type") is None:
        raise ValueError("partition search returned an invalid category")

    params = {
        "aid": 6383,
        "app_name": "douyin_web",
        "live_id": 1,
        "device_platform": "web",
        "language": "zh-CN",
        "browser_language": "zh-CN",
        "browser_platform": "Win32",
        "browser_name": "Chrome",
        "browser_version": "140.0.0.0",
        "partition": partition["id_str"],
        "partition_type": partition["type"],
        "count": 5,
        "offset": 0,
        "cookie_enabled": "true",
        "screen_width": 1920,
        "screen_height": 1080,
    }
    errors: list[str] = []
    for endpoint in (
        "https://live.douyin.com/webcast/web/partition/detail/room/v2/",
        "https://webcast.amemv.com/webcast/web/partition/detail/room/v2/",
    ):
        try:
            response = get_json(endpoint, params)
            require_path(response, "data", "data")
            rooms = response["data"]["data"]  # type: ignore[index]
            if isinstance(rooms, list) and rooms:
                return
            errors.append(f"{endpoint}: empty room list")
        except Exception as error:  # noqa: BLE001 - verify both production fallbacks
            errors.append(f"{endpoint}: {error}")
    raise ValueError("; ".join(errors))


def douyin_feed_probe() -> None:
    """Validate both the current feed-envelope shape and its room payload."""
    cookie_jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookie_jar))
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "application/json,text/plain,*/*",
        "Accept-Language": "zh-CN,zh;q=0.9",
        "Referer": "https://live.douyin.com/",
        "Connection": "close",
    }
    home_request = urllib.request.Request("https://live.douyin.com/?from_nav=1", headers=headers)
    with opener.open(home_request, timeout=20) as response:
        # Reading one byte and closing the bootstrap caused a repeatable false
        # 503 in this readiness probe. The application already consumes the
        # full response, so mirror that production lifecycle here.
        response.read()

    params = {
        "aid": 6383,
        "app_name": "douyin_web",
        "need_map": 1,
        "is_draw": 1,
        "inner_from_drawer": 0,
        "enter_source": "web_homepage_hot_web_live_card",
        "source_key": "web_homepage_hot_web_live_card",
    }
    request = urllib.request.Request(
        f"https://live.douyin.com/webcast/feed/?{urllib.parse.urlencode(params)}",
        headers=headers,
    )
    with opener.open(request, timeout=20) as response:
        payload = json.loads(response.read().decode("utf-8", errors="replace").lstrip("\ufeff"))

    if not isinstance(payload, dict) or payload.get("status_code") != 0:
        raise ValueError("Douyin feed request was rejected")
    rooms = payload.get("data")
    if isinstance(rooms, dict):
        rooms = rooms.get("data")
    if not isinstance(rooms, list) or not rooms:
        raise ValueError("Douyin feed room list is missing")

    for envelope in rooms:
        if not isinstance(envelope, dict):
            continue
        room = envelope.get("data", envelope)
        if isinstance(room, str):
            try:
                room = json.loads(room)
            except json.JSONDecodeError:
                continue
        if not isinstance(room, dict):
            continue
        owner = room.get("owner")
        web_rid = envelope.get("web_rid") or (owner.get("web_rid") if isinstance(owner, dict) else None)
        stream_url = room.get("stream_url")
        has_stream = isinstance(stream_url, dict) and any(
            stream_url.get(key) for key in ("live_core_sdk_data", "flv_pull_url", "hls_pull_url_map")
        )
        view_stats = room.get("room_view_stats") if isinstance(room.get("room_view_stats"), dict) else {}
        stats = room.get("stats") if isinstance(room.get("stats"), dict) else {}
        has_online = any(
            _audience_int(value) is not None
            for value in (
                room.get("user_count"),
                room.get("user_count_str"),
                view_stats.get("user_count"),
                view_stats.get("online_user_for_anchor"),
                stats.get("user_count"),
                stats.get("user_count_str"),
            )
        )
        if web_rid and room.get("title") and isinstance(room.get("cover"), dict) and has_stream and has_online:
            return
    raise ValueError("Douyin feed contains no playable room with an explicit online audience")


def bilibili_danmaku_probe() -> None:
    """Validate the signed endpoint and the current secure socket nodes."""
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

    def bili_json(url: str) -> dict[str, object]:
        request = urllib.request.Request(
            url,
            headers={
                "User-Agent": USER_AGENT,
                "Referer": "https://live.bilibili.com/6",
                "Accept": "application/json,text/plain,*/*",
            },
        )
        with opener.open(request, timeout=20) as response:
            return json.loads(response.read().decode("utf-8"))

    spi = bili_json("https://api.bilibili.com/x/frontend/finger/spi")
    require_path(spi, "data", "b_3")
    nav = bili_json("https://api.bilibili.com/x/web-interface/nav")
    wbi_img = nav.get("data", {}).get("wbi_img", {}) if isinstance(nav.get("data"), dict) else {}
    img_url = str(wbi_img.get("img_url", ""))
    sub_url = str(wbi_img.get("sub_url", ""))
    if not img_url or not sub_url:
        raise ValueError("WBI image keys missing")

    source = "".join(urllib.parse.urlsplit(url).path.rsplit("/", 1)[-1].split(".", 1)[0] for url in (img_url, sub_url))
    table = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
    ]
    mixin_key = "".join(source[index] for index in table if index < len(source))[:32]
    params = {"id": "6", "type": "0", "wts": str(int(time.time()))}
    filtered = {key: "".join(char for char in value if char not in "!'()*") for key, value in params.items()}
    query = urllib.parse.urlencode(sorted(filtered.items()))
    filtered["w_rid"] = hashlib.md5(f"{query}{mixin_key}".encode()).hexdigest()
    response = bili_json(
        "https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo?"
        + urllib.parse.urlencode(filtered)
    )
    if response.get("code") != 0:
        raise ValueError(f"getDanmuInfo code={response.get('code')}")
    data = response.get("data", {})
    hosts = data.get("host_list", []) if isinstance(data, dict) else []
    if not data.get("token") or not hosts:
        raise ValueError("danmaku token/host_list missing")
    for host in hosts:
        if not host.get("host") or int(host.get("wss_port", 0)) <= 0:
            raise ValueError("invalid secure danmaku endpoint")


def bilibili_recommend_probe() -> None:
    """Validate the anonymous popularity feed and a transformed cover URL."""
    response = request_json(
        "https://api.live.bilibili.com/room/v1/Area/getListByAreaID",
        {"areaId": 0, "parent_area_id": 0, "sort": "online", "pageSize": 30, "page": 1},
    )
    if not isinstance(response, dict) or response.get("code") != 0:
        raise ValueError(f"recommend code={response.get('code') if isinstance(response, dict) else 'invalid'}")
    rooms = response.get("data", [])
    if not rooms or not isinstance(rooms[0], dict):
        raise ValueError("popularity room list missing")
    if any(not str(room.get("online", "")).isdigit() for room in rooms if isinstance(room, dict)):
        raise ValueError("popularity value missing")
    cover = str(rooms[0].get("cover", "")).strip()
    if not cover.startswith("https://"):
        raise ValueError("recommend cover URL missing")
    cover_request = urllib.request.Request(
        f"{cover}@400w.jpg",
        headers={"User-Agent": USER_AGENT, "Referer": "https://live.bilibili.com/", "Accept": "image/*"},
    )
    with urllib.request.urlopen(cover_request, timeout=20) as cover_response:
        if cover_response.status != 200 or not cover_response.headers.get_content_type().startswith("image/"):
            raise ValueError(f"cover response={cover_response.status} {cover_response.headers.get_content_type()}")
        if len(cover_response.read(128)) < 64:
            raise ValueError("cover response is empty")


def bilibili_playback_probe() -> None:
    """Validate anonymous room playback descriptors and CDN URL components."""
    recommendation = request_json(
        "https://api.live.bilibili.com/room/v1/Area/getListByAreaID",
        {"areaId": 0, "parent_area_id": 0, "sort": "online", "pageSize": 10, "page": 1},
    )
    rooms = recommendation.get("data", []) if isinstance(recommendation, dict) else []
    if not rooms or not any(isinstance(room, dict) for room in rooms):
        raise ValueError("Bilibili playback probe has no live room")

    # The popularity endpoint is eventually consistent with the playback
    # service: a room can remain in the feed for a short period after its play
    # envelope becomes empty. Probe a bounded set instead of making the entire
    # release gate depend on the first transient room.
    failures: list[str] = []
    for room in (item for item in rooms[:5] if isinstance(item, dict)):
        room_id = str(room.get("roomid", "")).strip()
        if not room_id:
            failures.append("missing room id")
            continue
        try:
            response = request_json(
                "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo",
                {
                    "room_id": room_id,
                    "protocol": "0,1",
                    "format": "0,1,2",
                    "codec": "0,1",
                    "qn": 10000,
                    "platform": "web",
                    "ptype": 8,
                },
            )
            if not isinstance(response, dict) or response.get("code") != 0:
                failures.append(f"{room_id}: rejected")
                continue
            data = response.get("data", {})
            playurl_info = data.get("playurl_info", {}) if isinstance(data, dict) else {}
            playurl = playurl_info.get("playurl", {}) if isinstance(playurl_info, dict) else {}
            streams = playurl.get("stream", []) if isinstance(playurl, dict) else []
            qualities = playurl.get("g_qn_desc", []) if isinstance(playurl, dict) else []
            if not isinstance(streams, list) or not streams or not isinstance(qualities, list) or not qualities:
                failures.append(f"{room_id}: descriptors missing")
                continue

            for stream in streams:
                formats = stream.get("format", []) if isinstance(stream, dict) else []
                for format_item in formats if isinstance(formats, list) else []:
                    codecs = format_item.get("codec", []) if isinstance(format_item, dict) else []
                    for codec in codecs if isinstance(codecs, list) else []:
                        if not isinstance(codec, dict) or not codec.get("base_url"):
                            continue
                        url_info = codec.get("url_info", [])
                        if isinstance(url_info, list) and any(
                            isinstance(item, dict)
                            and str(item.get("host", "")).startswith(("http://", "https://"))
                            for item in url_info
                        ):
                            return
            failures.append(f"{room_id}: CDN URL missing")
        except Exception as error:  # noqa: BLE001 - retain per-room diagnostics
            failures.append(f"{room_id}: {error}")

    summary = "; ".join(failures[-5:]) or "no usable room id"
    raise ValueError(f"Bilibili playback candidates failed: {summary}")


def huya_danmaku_identity_probe() -> None:
    """Ensure a live room exposes the numeric uid required by the gateway."""
    recommendation = request_json(
        "https://www.huya.com/cache.php",
        {"m": "LiveList", "do": "getLiveListByPage", "tagAll": 0, "page": 1},
    )
    if not isinstance(recommendation, dict):
        raise ValueError("invalid recommendation response")
    data = recommendation.get("data", {})
    rooms = data.get("datas", []) if isinstance(data, dict) else []
    if not rooms or not isinstance(rooms[0], dict):
        raise ValueError("no live room available for identity probe")
    room_id = str(rooms[0].get("profileRoom", "")).strip()
    if not room_id:
        raise ValueError("recommended room id missing")

    detail = request_json(
        "https://mp.huya.com/cache.php",
        {"m": "Live", "do": "profileRoom", "roomid": room_id, "showSecret": 1},
    )
    if not isinstance(detail, dict) or detail.get("status") != 200:
        raise ValueError(f"room detail status={detail.get('status') if isinstance(detail, dict) else 'invalid'}")
    detail_data = detail.get("data", {})
    profile = detail_data.get("profileInfo", {}) if isinstance(detail_data, dict) else {}
    try:
        uid = int(profile.get("uid", 0)) if isinstance(profile, dict) else 0
    except (TypeError, ValueError) as error:
        raise ValueError("profileInfo.uid is not numeric") from error
    if uid <= 0:
        raise ValueError("profileInfo.uid missing")


def huya_playback_probe() -> None:
    """Validate profileRoom metadata, quality and FLV/HLS line descriptors."""
    recommendation = request_json(
        "https://www.huya.com/cache.php",
        {"m": "LiveList", "do": "getLiveListByPage", "tagAll": 0, "page": 1},
    )
    data = recommendation.get("data", {}) if isinstance(recommendation, dict) else {}
    rooms = data.get("datas", []) if isinstance(data, dict) else []
    room_id = str(rooms[0].get("profileRoom", "")).strip() if rooms and isinstance(rooms[0], dict) else ""
    if not room_id:
        raise ValueError("Huya playback room id missing")
    detail = request_json(
        "https://mp.huya.com/cache.php",
        {"m": "Live", "do": "profileRoom", "roomid": room_id, "showSecret": 1},
    )
    detail_data = detail.get("data", {}) if isinstance(detail, dict) and detail.get("status") == 200 else {}
    stream = detail_data.get("stream", {}) if isinstance(detail_data, dict) else {}
    base_streams = stream.get("baseSteamInfoList", []) if isinstance(stream, dict) else []
    live_data = detail_data.get("liveData", {}) if isinstance(detail_data, dict) else {}
    if not isinstance(base_streams, list) or not base_streams or not isinstance(live_data, dict):
        raise ValueError("Huya room stream/liveData missing")
    if not live_data.get("bitRateInfo") and not any(
        isinstance(value, dict) and value.get("rateArray") for value in stream.values()
    ):
        raise ValueError("Huya quality descriptors missing")
    for item in base_streams:
        if not isinstance(item, dict):
            continue
        if item.get("sStreamName") and (item.get("sFlvUrl") or item.get("sHlsUrl")):
            return
    raise ValueError("Huya playback response has no usable stream line")
















def _audience_int(value: object) -> int | None:
    if isinstance(value, bool) or value is None:
        return None
    try:
        return int(str(value).replace(",", "").strip())
    except ValueError:
        return None


def douyu_recommend_probe() -> None:
    rooms = require_path(request_json("https://www.douyu.com/japi/weblist/apinc/allpage/6/1"), "data", "rl")
    if not isinstance(rooms, list) or not rooms:
        raise ValueError("Douyu recommendation returned no rooms")
    if not any(isinstance(room, dict) and _audience_int(room.get("ol")) is not None for room in rooms):
        raise ValueError("Douyu ol heat field missing")


def huya_recommend_probe() -> None:
    rooms = require_path(
        request_json(
            "https://www.huya.com/cache.php",
            {"m": "LiveList", "do": "getLiveListByPage", "tagAll": 0, "page": 1},
        ),
        "data",
        "datas",
    )
    if not isinstance(rooms, list) or not rooms:
        raise ValueError("Huya recommendation returned no rooms")
    if not any(isinstance(room, dict) and _audience_int(room.get("totalCount")) is not None for room in rooms):
        raise ValueError("Huya totalCount heat field missing")


def kuaishou_home_probe() -> None:
    groups = require_path(request_json("https://live.kuaishou.com/live_api/home/list"), "data", "list")
    if not isinstance(groups, list) or not groups:
        raise ValueError("Kuaishou home returned no groups")
    rooms: list[dict[str, object]] = []
    for group in groups:
        if not isinstance(group, dict):
            continue
        for game_group in group.get("gameLiveInfo", []):
            if isinstance(game_group, dict):
                rooms.extend(room for room in game_group.get("liveInfo", []) if isinstance(room, dict))
    if not rooms:
        raise ValueError("Kuaishou home returned no room cards")
    if not any(_audience_int(room.get("watchingCount")) is not None for room in rooms):
        raise ValueError("Kuaishou watchingCount missing")





def main() -> int:
    probes = [
        (
            "bilibili.categories",
            lambda: require_path(
                request_json("https://api.live.bilibili.com/room/v1/Area/getList", {"need_entrance": 1, "parent_id": 0}),
                "data",
            ),
        ),
        (
            "douyu.categories",
            lambda: require_path(request_json("https://m.douyu.com/api/cate/list"), "data", "cate1Info"),
        ),
        ("douyu.recommend", douyu_recommend_probe),
        ("douyu.encryption", douyu_encryption_probe),
        ("douyu.playback", douyu_playback_probe),
        ("douyu.reported_room_799", douyu_reported_room_probe),
        (
            "huya.categories",
            lambda: require_path(
                request_json("https://live.cdn.huya.com/liveconfig/game/bussLive", {"bussType": 1}), "data"
            ),
        ),
        ("huya.recommend", huya_recommend_probe),
        (
            "kuaishou.categories",
            lambda: require_path(
                request_json("https://live.kuaishou.com/live_api/category/data", {"type": 1, "page": 1, "size": 30}),
                "data",
                "list",
            ),
        ),
        ("kuaishou.home", kuaishou_home_probe),
        ("kuaishou.playback", kuaishou_playback_probe),
        ("bilibili.popularity_rank", bilibili_recommend_probe),
        ("bilibili.playback", bilibili_playback_probe),
        ("bilibili.danmaku", bilibili_danmaku_probe),
        ("huya.danmaku_identity", huya_danmaku_identity_probe),
        ("huya.playback", huya_playback_probe),
        ("douyin.feed", douyin_feed_probe),
        ("douyin.search", douyin_search_probe),
        ("douyu.search", douyu_search_probe),
        (
            "huya.search",
            lambda: require_path(
                request_json(
                    "https://search.cdn.huya.com/",
                    {
                        "m": "Search",
                        "do": "getSearchContent",
                        "q": "ASMR",
                        "uid": 0,
                        "v": 4,
                        "typ": -5,
                        "livestate": 0,
                        "rows": 20,
                        "start": 0,
                    },
                ),
                "response",
            ),
        ),
    ]

    failures: list[str] = []
    for name, probe in probes:
        try:
            probe()
            print(f"PASS {name}")
        except Exception as error:  # noqa: BLE001 - command-line diagnostic
            failures.append(name)
            print(f"FAIL {name}: {error}")

    try:
        last_error: Exception | None = None
        for attempt in range(1, 4):
            try:
                request = urllib.request.Request(
                    "https://live.douyin.com/?from_nav=1",
                    headers={"User-Agent": USER_AGENT, "Connection": "close"},
                )
                with urllib.request.urlopen(request, timeout=20) as response:
                    html = response.read().decode("utf-8", errors="replace")
                    cookies = response.headers.get_all("Set-Cookie") or []
                if r'{\"pathname\":\"/\",\"categoryData\":' not in html:
                    raise ValueError("categoryData marker missing")
                if not any(cookie.startswith("ttwid=") for cookie in cookies):
                    raise ValueError("anonymous ttwid cookie missing")
                break
            except Exception as error:  # noqa: BLE001 - bounded transient retry
                last_error = error
                if attempt < 3:
                    time.sleep(attempt)
        else:
            assert last_error is not None
            raise last_error
        print("PASS douyin.home")
    except Exception as error:  # noqa: BLE001 - command-line diagnostic
        failures.append("douyin.home")
        print(f"FAIL douyin.home: {error}")

    print(f"SUMMARY {len(probes) + 1 - len(failures)}/{len(probes) + 1} passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
