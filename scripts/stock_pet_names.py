"""Display names for distinct managed Pet profiles, never human accounts."""

DOG_NAMES = [
    'こむぎ', 'まる', 'そら', 'レオ', 'モカ', 'はる', 'だいふく', 'くう', 'コロ', 'ふうた',
    'ぽんず', 'むぎ', 'ルーク', 'とわ', 'しろ', 'ノア', 'ポテト', 'てん', 'こたろう',
    'はち', 'ももすけ', 'バロン', 'きなこ丸', 'らい', 'さんぽ',
]
CAT_NAMES = [
    'つむぎ', 'もち', 'みるく', 'こはく', 'あずき', 'ルナ', 'すず', 'きなこ', 'しらたま',
    'めい', 'くるみ', 'ちょこ', 'にこ', 'おもち', 'りん', 'ひなた', 'ゆず', 'あんず',
    'こてつ', 'ふく', 'あお', 'ちびた', 'いちご', 'うに', 'すみれ',
]


def name_for(species, ordinal):
    names = DOG_NAMES if species == 'dog' else CAT_NAMES
    return names[ordinal % len(names)]
