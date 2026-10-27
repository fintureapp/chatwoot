# Identidade visual Finture no Chatwoot

Fonte da marca: Drive `iasegurosfinture@gmail.com` → `01_FINTURE/` (manual de marca, logos e
paleta). Em caso de dúvida, o manual oficial prevalece sobre este resumo.

## Onde ficam os tokens

| O quê | Arquivo |
|---|---|
| Cores (claro e escuro) | `app/javascript/dashboard/assets/scss/_next-colors.scss` |
| Mapa para o Tailwind (`n-*`) | `theme/colors.js` e `tailwind.config.js` |
| Fontes | `app/javascript/shared/assets/fonts/finture.scss` |
| Hex para JavaScript | `app/javascript/dashboard/constants/brand.js` |
| Logos e favicons | `public/brand-assets/*.svg` e `public/*.png` |

As três cores oficiais existem uma vez só, em `--finture-orange` (#EA622D), `--finture-ink`
(#1B1A1A) e `--finture-offwhite` (#F8F1E7). Tudo o mais deriva delas.

## Como usar nas telas

| Precisa de | Use | Observação |
|---|---|---|
| Ação principal, destaque, indicador | `bg-n-brand` | Laranja oficial |
| Texto sobre `bg-n-brand` | `text-n-brand-contrast` | Preto Finture (5.2:1). **Não use `text-white`**: dá 3.3:1 |
| Texto ou link em laranja | `text-n-brand` ou `text-n-blue-11` | Tom escurecido automático (5.2:1 no branco) |
| Escala de destaque (fundos suaves, hover) | `n-blue-1` … `n-blue-12` | O nome "blue" veio do upstream; os valores são o laranja |
| Texto principal / secundário | `text-n-slate-12` / `text-n-slate-11` | Neutros quentes |
| Fundo de navegação | `bg-n-background` | Off-white (claro) e Preto Finture (escuro) |
| Área de trabalho | `bg-n-surface-1` | Branco (claro) |
| Sucesso / alerta / erro | `n-teal-*` / `n-amber-*` / `n-ruby-*` | Mantidos distintos do laranja |
| Títulos | `font-heading` (h1–h6 já usam) | IBM Plex Sans |
| Corpo | padrão (`font-sans`) | Space Grotesk |

Não escreva hex nem cores do Tailwind padrão (`bg-orange-500`, `#EA622D`) direto nos
componentes. Se faltar um token, crie em `_next-colors.scss` para os dois temas.

## Logos

Os SVGs em `public/brand-assets/` só embutem os PNGs oficiais do Drive, recortados e sem
redesenho, como o manual exige. Mantêm os caminhos padrão do Chatwoot (`LOGO`, `LOGO_DARK`,
`LOGO_THUMBNAIL`), então instalações com o valor padrão pegam a troca sem mexer no banco.

- `logo.svg`: logo principal colorida (fundo claro)
- `logo_dark.svg`: logo monocromática branca (fundo escuro)
- `logo_thumbnail.svg`: símbolo isolado (sidebar)

O nome exibido ("Entrar no …", título da aba) vem de `INSTALLATION_NAME` e `BRAND_NAME` em
Super Admin → Installation Config, não do código.
