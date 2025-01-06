#!/bin/sh
set -xe

APP_DIR="/app"

# Remove uma potencial pid existente do servidor Rails e limpa cache
rm -rf "$APP_DIR/tmp/pids/server.pid"
rm -rf "$APP_DIR/tmp/cache/*"

# Certifique-se de estar no diretório da aplicação
cd "$APP_DIR" || {
  echo "Erro: não foi possível acessar o diretório $APP_DIR."
  exit 1
}

# Verifica se existe um Gemfile
if [ ! -f "$APP_DIR/Gemfile" ]; then
  echo "Erro: Gemfile não encontrado em $APP_DIR. Saindo..."
  exit 1
fi

echo "Waiting for postgres to become ready...."

# Caminho absoluto para o script pg_database_url.rb
PG_DATABASE_URL_SCRIPT="/app/docker/entrypoints/helpers/pg_database_url.rb"

# Verifica se o script pg_database_url.rb existe
if [ ! -f "$PG_DATABASE_URL_SCRIPT" ]; then
  echo "Erro: O script $PG_DATABASE_URL_SCRIPT não foi encontrado."
  exit 1
fi

# Verifica se o script é executável; se não for, tenta dar permissão
if [ ! -x "$PG_DATABASE_URL_SCRIPT" ]; then
  echo "Aviso: O script $PG_DATABASE_URL_SCRIPT não é executável. Ajustando permissões..."
  chmod +x "$PG_DATABASE_URL_SCRIPT"
fi

# Executa o script Ruby para configurar a URL do banco de dados
ruby "$PG_DATABASE_URL_SCRIPT"

# Configura o comando pg_isready com as variáveis de ambiente
PG_READY="pg_isready -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USERNAME"

# (Opcional) limite de tentativas para o pg_isready, evitando loop infinito
MAX_POSTGRES_RETRIES=20
POSTGRES_RETRIES=0

# Aguarda até que o PostgreSQL esteja pronto para aceitar conexões
until $PG_READY; do
  POSTGRES_RETRIES=$((POSTGRES_RETRIES + 1))
  if [ "$POSTGRES_RETRIES" -ge "$MAX_POSTGRES_RETRIES" ]; then
    echo "Erro: Postgres não ficou pronto após $MAX_POSTGRES_RETRIES tentativas. Abortando."
    exit 1
  fi
  echo "Postgres ainda não está pronto. Tentando novamente em 2 segundos..."
  sleep 2
done

echo "Database ready to accept connections."

# Instala as gems faltantes
echo "Executando bundle install..."
bundle install

# Verifica se todas as gems estão instaladas
MAX_GEM_RETRIES=10
gem_retries=0

until bundle check; do
  gem_retries=$((gem_retries + 1))
  if [ "$gem_retries" -ge "$MAX_GEM_RETRIES" ]; then
    echo "Erro: Falhou ao verificar/installar gems após $MAX_GEM_RETRIES tentativas. Abortando."
    exit 1
  fi

  echo "Gems ainda não estão instaladas corretamente. Tentando novamente em 2 segundos..."
  sleep 2

  # Tenta instalar novamente caso seja um erro temporário
  bundle install
done

echo "Todas as gems estão instaladas corretamente."

# Executa o processo principal do contêiner (comando fornecido via CMD ou argumentos)
exec "$@"
