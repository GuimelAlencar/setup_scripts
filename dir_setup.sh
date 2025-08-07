#!/bin/bash

# Função para criar diretório com verificação
criar_diretorio() {
    local dir="$1"
    local descricao="$2"
    
    if [ -d "$dir" ]; then
        echo "Diretório $descricão já existe: $dir"
        if [ "$(ls -A "$dir")" ]; then
            read -p "O diretório contém arquivos. Deseja apagar e recriar? (s/N) " resposta
            if [[ "$resposta" =~ ^[sS]$ ]]; then
                rm -rf "$dir"
                mkdir -p "$dir"
                echo "Diretório recriado: $dir"
            else
                echo "Pulando diretório $dir"
            fi
        else
            read -p "Diretório vazio. Recriar? (s/N) " resposta
            if [[ "$resposta" =~ ^[sS]$ ]]; then
                rm -rf "$dir"
                mkdir -p "$dir"
                echo "Diretório recriado: $dir"
            fi
        fi
    else
        mkdir -p "$dir"
        echo "Diretório criado: $dir"
    fi
}

# Diretório base
BASE_DIR="$HOME/desktop"

# Mapeamento de diretórios a serem criados (descrição: caminho)
declare -A DIRETORIOS=(
    ["Main Desktop"]="$BASE_DIR"
    ["Dev Directory"]="$BASE_DIR/dev"
    ["Python projects"]="$BASE_DIR/dev/py"
    ["DevOps Directory"]="$BASE_DIR/dev_ops"
    ["Virtualization"]="$BASE_DIR/dev_ops/virt"
    ["Docker"]="$BASE_DIR/dev_ops/virt/dkr"
)

# Processar cada diretório
for descricao in "${!DIRETORIOS[@]}"; do
    criar_diretorio "${DIRETORIOS[$descricao]}" "$descricao"
done

echo "Estrutura de diretórios criada com sucesso!"
