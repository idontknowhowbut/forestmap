To apply the Keycloak theme to an existing forestmap realm:
1. Ensure the theme files are mounted into /opt/keycloak/themes/forestmap
2. In Keycloak admin console open Realm settings -> Themes
3. Set Login theme = forestmap
If the realm is imported from infra/forestmap-realm-export.json on a clean Keycloak database,
the login theme is applied automatically.
