# Sincronização Musify Cloud - Guia Interno

## Visão Geral

Este projeto mantém duas branches principais:
- **`master`** (desktop): port para Windows/Linux do Musify com sync opcional
- **`mobile-cloud-sync`** (mobile): build Android do Musify Cloud

Ambas sincronizam com `gokadzev/Musify` upstream mantendo features específicas.

## Estado Atual (v10.1.0)

| Branch | Status | Upstream |
|--------|--------|----------|
| `mobile-cloud-sync` | ✅ Sincronizado 10.0.10 | 10.1.0 disponível |
| `master` | ⏳ Atrasado (10.0.10) | 10.1.0 disponível |

## Conflitos Conhecidos

Ao sincronizar upstream com branches locais, espere conflitos em:

### `lib/screens/settings_page.dart`
**Importações**: Mobile Cloud adiciona `backed_up_state_manager`, `cloud_sync_manager` + extras
**Restauração de dados**: 
- LOCAL (mobile-cloud-sync): `refreshBackedUpStateFromStorage()` + Cloud listeners
- UPSTREAM: `reloadSongLibraryStateFromStorage()` + `wrappedEnabled` + `listeningStatsService.reload()`
- **RESOLUÇÃO**: Preservar AMBAS - local prepara Cloud, upstream recarrega estado

### `lib/services/common_services.dart`
**Funções de carregamento**:
- LOCAL: `refreshUserSongsFromStorage()` com `recentlyPlayedVersion.value++`
- UPSTREAM: `reloadSongLibraryStateFromStorage()` com `List.from()` para imutabilidade
- **RESOLUÇÃO**: Manter AMBAS - elas servem propósitos diferentes

### `pubspec.lock` / `pubspec.yaml`
- Gerados/Atualizados automaticamente durante merge
- **RESOLUÇÃO**: Aceitar versão upstream (sempre mais nova)

## Workflow de Sincronização

### Automático (Scheduled)
```bash
# Dispara a cada 6 horas (cron: "17 */6 * * *")
# Resolve-se com -X ours em caso de conflito (preserva local)
```

### Manual
```bash
# Mobile-Cloud-Sync com tag específica
git fetch upstream --no-tags --prune +refs/tags/10.1.0:refs/tags/10.1.0
git checkout -b temp-sync mobile-cloud-sync
git merge --no-edit refs/tags/10.1.0

# Em caso de conflito:
# 1. settings_page.dart: aceitar AMBOS os blocos
# 2. common_services.dart: aceitar AMBAS as funções
# 3. pubspec: aceitar upstream

git add .
git commit -m "Merge upstream X.Y.Z into mobile-cloud-sync; preserve Musify Cloud features"
git push origin HEAD:refs/heads/mobile-cloud-sync
```

## Release Workflow

### Mobile Cloud (Android)
```bash
gh workflow run mobile_release.yml \
  --ref refs/heads/mobile-cloud-sync \
  -f version="10.1.0" \
  -f source_ref="refs/heads/mobile-cloud-sync" \
  -f repair_existing_release=false
```

Resultado: `mobile-v10.1.0` release (não marked as Latest)

### Desktop (Windows/Linux)
Workflow ainda não implementado - requer:
- Desktop build para Windows (.msi)
- Desktop build para Linux (.AppImage)
- Tag: `desktop-v10.1.0` (marked as Latest)

## Troubleshooting

### Workflow falha com merge conflict
1. Clonar localmente
2. Resolver conflitos conforme acima
3. Push para mobile-cloud-sync
4. Disparar workflow manualmente: `gh workflow run mobile_release.yml ...`

### Já existe mobile-v10.1.0
- Workflow detecta e pula merge se release completa existe
- Para reconstruir: adicionar `-f repair_existing_release=true`

### Imports faltando
Se código compilar mas faltar imports após sync:
- Verificar se as funções de backup estão em `backed_up_state_manager.dart`
- Verificar se `listening_stats_service` está disponível
- Rodar `flutter pub get`

## Próximos Passos

- [ ] Implementar desktop_release.yml
- [ ] Auto-sync master com upstream também
- [ ] Criar desktop-v10.1.0 release
- [ ] Testar sync automático com -X ours fallback
