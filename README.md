# TOTP

> Generate TOTP codes RFC-6238

# CLI Quick Start

Add a provider and generate code:
```
$ zotp a <server> <token>

$ zotp g <server>
123456
```

List all providers:
```
$ zotp l
$ zotp list
```

Delete a provider:
```
$ zotp delete <server>
$ zotp d <server>
```

Uninstall:
```
$ zotp uninstall
```
This will delete `.config/zotp`

