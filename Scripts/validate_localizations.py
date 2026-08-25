#!/usr/bin/env python3
"""Validate the iPhone String Catalog's required locales and representative values."""
import json
from pathlib import Path

catalog = json.loads((Path(__file__).parents[1] / "Localizable.xcstrings").read_text())
expected = {
    "en": {"5h remaining": "5h remaining", "Weekly": "Weekly", "Reset —": "Reset —", "Cached": "Cached", "account.number": "Account %lld"},
    "ja": {"5h remaining": "残り5時間", "Weekly": "週間", "Reset —": "リセット —", "Cached": "キャッシュ", "account.number": "アカウント%lld"},
    "zh-Hans": {"5h remaining": "剩余 5 小时", "Weekly": "每周", "Reset —": "重置 —", "Cached": "缓存数据", "account.number": "账户 %lld"},
    "zh-Hant": {"5h remaining": "剩餘 5 小時", "Weekly": "每週", "Reset —": "重設 —", "Cached": "快取資料", "account.number": "帳戶 %lld"},
    "ko": {"5h remaining": "5시간 남음", "Weekly": "주간", "Reset —": "초기화 —", "Cached": "캐시됨", "account.number": "계정 %lld"},
}
strings = catalog["strings"]
for locale, translations in expected.items():
    for key, value in translations.items():
        actual = strings[key]["localizations"][locale]["stringUnit"]["value"]
        assert actual == value, f"{locale} {key!r}: expected {value!r}, got {actual!r}"
for key, entry in strings.items():
    missing = expected.keys() - entry.get("localizations", {}).keys()
    assert not missing, f"{key!r} is missing {sorted(missing)}"
print(f"Validated {len(strings)} keys in {len(expected)} locales")
