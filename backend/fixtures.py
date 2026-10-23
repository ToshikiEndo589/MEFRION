"""Owned procedural illustrations; no web photographs or real identities."""
PETS = [
    {"id": f"demo-{i}", "name": name, "species": species, "asset": f"pet-{i}",
     "demo_only": True, "rights": "project-owned-procedural-illustration",
     "content_origin": "managed_seed", "publisher_id": "demo-publisher",
     "public": True, "twins_consent": True}
    for i, (name, species) in enumerate([
        ("こむぎ", "dog"), ("きなこ", "cat"), ("まる", "dog"),
        ("むぎ", "cat"), ("そら", "dog"), ("はな", "cat"),
        ("モカ", "dog"), ("ゆず", "cat"), ("ルカ", "dog"), ("りん", "cat")
    ])
]

def feed():
    # Public projection deliberately omits publisher, origin and rights evidence.
    return [{"id": "demo-post-"+p["id"], "pet_id": p["id"], "name": p["name"],
             "species": p["species"], "asset": p["asset"],
             "body": "犬猫を描いた開発用イラストです。", "demo_only": True,
             "likes": 0, "comments": 0} for p in PETS]
