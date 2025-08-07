#!/bin/bash

# Docker Setup Script - Instalação, Desinstalação e Pós-Instalação
# Compatível com Ubuntu 24.04 LTS
# Versão: 2.1.0
# Autor: Sistema de Automação Docker
# Data: $(date +%Y-%m-%d)

SCRIPT_VERSION="2.1.0"
SCRIPT_NAME="Docker Setup Script"

# Funções de log
log_info() {
    echo "[INFO] $1"
}

log_success() {
    echo "[SUCCESS] $1"
}

log_warning() {
    echo "[WARNING] $1"
}

log_error() {
    echo "[ERROR] $1"
}

# Verifica se é Ubuntu 24.04 LTS
check_ubuntu_version() {
    if [ ! -f /etc/os-release ]; then
        log_error "Não foi possível determinar a versão do sistema operacional"
        exit 1
    fi
    
    . /etc/os-release
    
    if [ "$ID" != "ubuntu" ]; then
        log_error "Este script é compatível apenas com Ubuntu"
        log_error "Sistema detectado: $ID"
        exit 1
    fi
    
    if [ "$VERSION_ID" != "24.04" ]; then
        log_warning "Este script foi testado no Ubuntu 24.04 LTS"
        log_warning "Sistema detectado: Ubuntu $VERSION_ID"
        read -p "Deseja continuar mesmo assim? (y/n): " choice
        case "$choice" in
            y|Y ) log_info "Continuando...";;
            * ) log_error "Operação cancelada pelo usuário"; exit 1;;
        esac
    else
        log_success "Sistema compatível: Ubuntu 24.04 LTS"
    fi
}

# Verifica se é executado como root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Este script deve ser executado como root/sudo"
        exit 1
    fi
}

# Verifica se é executado como usuário normal (não root)
check_user() {
    if [ "$EUID" -eq 0 ]; then
        log_error "Esta operação deve ser executada como usuário normal (não root)"
        exit 1
    fi
}

# Confirmação do usuário
confirm_continue() {
    read -p "$1 (y/n)? " choice
    case "$choice" in
        y|Y ) log_info "Continuando...";;
        * ) log_error "Operação cancelada pelo usuário"; exit 1;;
    esac
}

# Função para verificar erros
check_error() {
    if [ $? -ne 0 ]; then
        log_error "Falha no comando: $1"
        return 1
    fi
    return 0
}

# Função para verificar conectividade com a internet
check_connectivity() {
    log_info "Verificando conectividade com a internet..."
    
    # Lista de hosts para testar conectividade
    local hosts=(
        "8.8.8.8"                           # Google DNS
        "download.docker.com"               # Docker repository
        "archive.ubuntu.com"                # Ubuntu repository
    )
    
    local connected=false
    
    for host in "${hosts[@]}"; do
        if ping -c 1 -W 3 "$host" &> /dev/null; then
            log_success "Conectividade confirmada com $host"
            connected=true
            break
        else
            log_warning "Falha ao conectar com $host"
        fi
    done
    
    if [ "$connected" = false ]; then
        log_error "Não foi possível estabelecer conectividade com a internet"
        log_error "Verifique sua conexão de rede e tente novamente"
        return 1
    fi
    
    return 0
}

# Variáveis globais para rollback
ROLLBACK_ACTIONS=()
ROLLBACK_FILES=()
ROLLBACK_PACKAGES=()

# Função para adicionar ação de rollback
add_rollback_action() {
    ROLLBACK_ACTIONS+=("$1")
}

# Função para adicionar arquivo de rollback
add_rollback_file() {
    if [ -f "$1" ]; then
        cp "$1" "${1}.backup.$(date +%s)" 2>/dev/null
        ROLLBACK_FILES+=("$1")
    fi
}

# Função para adicionar pacote de rollback
add_rollback_package() {
    ROLLBACK_PACKAGES+=("$1")
}

# Função para executar rollback
execute_rollback() {
    log_warning "Iniciando processo de rollback..."
    
    # Rollback de pacotes instalados
    if [ ${#ROLLBACK_PACKAGES[@]} -gt 0 ]; then
        log_info "Removendo pacotes instalados durante esta sessão..."
        for package in "${ROLLBACK_PACKAGES[@]}"; do
            log_info "Removendo pacote: $package"
            apt-get remove -y "$package" 2>/dev/null || true
        done
    fi
    
    # Rollback de arquivos
    if [ ${#ROLLBACK_FILES[@]} -gt 0 ]; then
        log_info "Restaurando arquivos modificados..."
        for file in "${ROLLBACK_FILES[@]}"; do
            local backup_file="${file}.backup.*"
            local latest_backup=$(ls -t ${backup_file} 2>/dev/null | head -1)
            if [ -f "$latest_backup" ]; then
                log_info "Restaurando: $file"
                cp "$latest_backup" "$file" 2>/dev/null || true
                rm -f ${file}.backup.* 2>/dev/null || true
            fi
        done
    fi
    
    # Rollback de ações customizadas
    if [ ${#ROLLBACK_ACTIONS[@]} -gt 0 ]; then
        log_info "Executando ações de rollback customizadas..."
        for action in "${ROLLBACK_ACTIONS[@]}"; do
            log_info "Executando: $action"
            eval "$action" 2>/dev/null || true
        done
    fi
    
    # Limpeza final
    log_info "Executando limpeza final..."
    apt-get autoremove -y 2>/dev/null || true
    apt-get autoclean 2>/dev/null || true
    
    log_warning "Rollback concluído. Algumas alterações podem requer reinicialização do sistema."
}

# Função para limpar arquivos de backup
cleanup_rollback() {
    # Remove arquivos de backup antigos
    for file in "${ROLLBACK_FILES[@]}"; do
        rm -f ${file}.backup.* 2>/dev/null || true
    done
    
    # Limpa arrays
    ROLLBACK_ACTIONS=()
    ROLLBACK_FILES=()
    ROLLBACK_PACKAGES=()
}

# Verifica se o Docker está instalado
check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        return 1
    else
        return 0
    fi
}

# Função de instalação
install_docker() {
    log_info "=== INICIANDO INSTALAÇÃO DO DOCKER ==="
    check_root
    
    # Verificar conectividade antes de começar
    if ! check_connectivity; then
        log_error "Instalação cancelada devido à falta de conectividade"
        exit 1
    fi
    
    # Inicializar rollback
    ROLLBACK_ACTIONS=()
    ROLLBACK_FILES=()
    ROLLBACK_PACKAGES=()
    
    # Trap para executar rollback em caso de erro
    trap 'log_error "Instalação falhada. Iniciando rollback..."; execute_rollback; exit 1' ERR
    
    # Etapa 1: Remover pacotes conflitantes
    confirm_continue "Deseja remover pacotes conflitantes (docker.io, podman, etc)"
    log_info "Removendo pacotes conflitantes..."
    
    # Registrar pacotes instalados para possível rollback
    local conflicting_packages=(docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc)
    local installed_conflicting=()
    
    for pkg in "${conflicting_packages[@]}"; do
        if dpkg -l | grep -q "^ii.*$pkg"; then
            installed_conflicting+=("$pkg")
            add_rollback_action "apt-get install -y $pkg"
        fi
        apt-get remove -y "$pkg" 2>/dev/null || true
    done
    log_success "Pacotes conflitantes removidos"

    # Etapa 2: Adicionar chave GPG
    log_info "Configurando repositório Docker..."
    apt-get update -y
    if ! check_error "apt-get update"; then
        execute_rollback
        exit 1
    fi
    
    apt-get install -y ca-certificates curl
    if ! check_error "apt-get install ca-certificates curl"; then
        execute_rollback
        exit 1
    fi
    add_rollback_package "ca-certificates"
    add_rollback_package "curl"
    
    # Backup do diretório keyrings se existir
    if [ -d "/etc/apt/keyrings" ]; then
        add_rollback_file "/etc/apt/keyrings"
    fi
    
    install -m 0755 -d /etc/apt/keyrings
    if ! check_error "install keyrings directory"; then
        execute_rollback
        exit 1
    fi
    add_rollback_action "rmdir /etc/apt/keyrings 2>/dev/null || true"
    
    # Download da chave GPG com verificação de conectividade
    log_info "Baixando chave GPG do Docker..."
    if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc; then
        log_error "Falha ao baixar chave GPG do Docker"
        execute_rollback
        exit 1
    fi
    add_rollback_action "rm -f /etc/apt/keyrings/docker.asc"
    
    chmod a+r /etc/apt/keyrings/docker.asc
    if ! check_error "chmod docker.asc"; then
        execute_rollback
        exit 1
    fi
    log_success "Chave GPG adicionada com sucesso"

    # Etapa 3: Adicionar repositório
    log_info "Adicionando repositório Docker..."
    
    # Backup da lista de sources se existir
    add_rollback_file "/etc/apt/sources.list.d/docker.list"
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
    if ! check_error "tee docker.list"; then
        execute_rollback
        exit 1
    fi
    add_rollback_action "rm -f /etc/apt/sources.list.d/docker.list"
    
    apt-get update -y
    if ! check_error "apt-get update"; then
        execute_rollback
        exit 1
    fi
    log_success "Repositório Docker adicionado"

    # Etapa 4: Instalar Docker
    confirm_continue "Deseja instalar Docker CE e plugins"
    log_info "Instalando Docker..."
    
    local docker_packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
    
    apt-get install -y "${docker_packages[@]}"
    if ! check_error "apt-get install docker"; then
        execute_rollback
        exit 1
    fi
    
    # Adicionar pacotes para rollback
    for pkg in "${docker_packages[@]}"; do
        add_rollback_package "$pkg"
    done
    
    log_success "Docker instalado com sucesso"

    # Etapa 5: Verificar instalação
    confirm_continue "Deseja verificar a instalação com hello-world"
    log_info "Executando hello-world..."
    
    # Aguardar o serviço Docker iniciar
    systemctl start docker
    sleep 3
    
    if ! docker run --rm hello-world; then
        log_error "Falha na verificação do Docker"
        execute_rollback
        exit 1
    fi
    log_success "Docker está funcionando corretamente!"

    # Etapa 6: Configurar usuário normal (opcional)
    if [ -n "$SUDO_USER" ]; then
        read -p "Deseja adicionar o usuário $SUDO_USER ao grupo docker (recomendado)? (y/n): " choice
        case "$choice" in
            y|Y )
                log_info "Adicionando usuário $SUDO_USER ao grupo docker..."
                usermod -aG docker "$SUDO_USER"
                if ! check_error "usermod -aG docker"; then
                    log_warning "Falha ao adicionar usuário ao grupo docker, mas instalação continuará"
                else
                    log_success "Usuário $SUDO_USER adicionado ao grupo docker"
                    log_warning "É necessário fazer logout e login novamente para aplicar as alterações"
                fi
                ;;
            * )
                log_warning "Lembre-se de executar comandos docker com sudo ou configurar manualmente"
                ;;
        esac
    fi

    # Remover trap e limpar rollback (instalação bem-sucedida)
    trap - ERR
    cleanup_rollback
    
    log_success "Instalação do Docker concluída com sucesso!"
    log_info "Execute './docker_setup.sh --post-install' como usuário normal para configurações adicionais"
}

# Função de desinstalação
uninstall_docker() {
    log_info "=== INICIANDO DESINSTALAÇÃO DO DOCKER ==="
    check_root
    
    if ! check_docker_installed; then
        log_warning "Docker não parece estar instalado neste sistema"
        confirm_continue "Deseja continuar mesmo assim"
    fi

    # Inicializar rollback para desinstalação
    ROLLBACK_ACTIONS=()
    ROLLBACK_FILES=()
    ROLLBACK_PACKAGES=()
    
    # Trap para rollback em caso de erro durante desinstalação
    trap 'log_error "Desinstalação falhada. Iniciando rollback..."; execute_rollback; exit 1' ERR

    # Etapa 1: Parar serviços Docker
    log_info "Parando serviços Docker..."
    systemctl stop docker 2>/dev/null || true
    systemctl stop containerd 2>/dev/null || true
    add_rollback_action "systemctl start docker 2>/dev/null || true"
    add_rollback_action "systemctl start containerd 2>/dev/null || true"

    # Etapa 2: Backup de dados (opcional)
    if [ -d "/var/lib/docker" ]; then
        read -p "Deseja fazer backup dos dados do Docker antes de remover? (y/n): " backup_choice
        case "$backup_choice" in
            y|Y )
                local backup_dir="/tmp/docker_backup_$(date +%Y%m%d_%H%M%S)"
                log_info "Criando backup em $backup_dir..."
                mkdir -p "$backup_dir"
                tar -czf "$backup_dir/docker_data.tar.gz" -C /var/lib docker 2>/dev/null || true
                tar -czf "$backup_dir/containerd_data.tar.gz" -C /var/lib containerd 2>/dev/null || true
                log_success "Backup criado em $backup_dir"
                add_rollback_action "tar -xzf $backup_dir/docker_data.tar.gz -C /var/lib/ 2>/dev/null || true"
                add_rollback_action "tar -xzf $backup_dir/containerd_data.tar.gz -C /var/lib/ 2>/dev/null || true"
                ;;
        esac
    fi

    # Etapa 3: Remover pacotes Docker
    confirm_continue "Deseja remover todos os pacotes Docker"
    log_info "Removendo pacotes Docker..."
    
    local docker_packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras)
    
    for pkg in "${docker_packages[@]}"; do
        if dpkg -l | grep -q "^ii.*$pkg" 2>/dev/null; then
            add_rollback_action "apt-get install -y $pkg"
        fi
    done
    
    apt-get purge -y "${docker_packages[@]}" 2>/dev/null || true
    if ! check_error "apt-get purge docker packages"; then
        execute_rollback
        exit 1
    fi
    log_success "Pacotes Docker removidos"

    # Etapa 4: Remover dados persistentes
    confirm_continue "Deseja remover TODOS os dados do Docker (imagens, containers, volumes)"
    log_info "Removendo dados persistentes..."
    
    if [ -d "/var/lib/docker" ]; then
        add_rollback_file "/var/lib/docker"
        rm -rf /var/lib/docker
        if ! check_error "rm /var/lib/docker"; then
            execute_rollback
            exit 1
        fi
    fi
    
    if [ -d "/var/lib/containerd" ]; then
        add_rollback_file "/var/lib/containerd"
        rm -rf /var/lib/containerd
        if ! check_error "rm /var/lib/containerd"; then
            execute_rollback
            exit 1
        fi
    fi
    log_success "Dados persistentes removidos"

    # Etapa 5: Remover configurações
    confirm_continue "Deseja remover configurações do Docker (repositórios, chaves)"
    log_info "Removendo configurações..."
    
    add_rollback_file "/etc/apt/sources.list.d/docker.list"
    add_rollback_file "/etc/apt/keyrings/docker.asc"
    
    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /etc/apt/keyrings/docker.asc
    log_success "Configurações removidas"

    # Etapa 6: Limpeza final
    log_info "Realizando limpeza final do sistema..."
    apt-get autoremove -y
    if ! check_error "apt-get autoremove"; then
        log_warning "Falha na limpeza automática, mas continuando..."
    fi
    apt-get autoclean
    if ! check_error "apt-get autoclean"; then
        log_warning "Falha na limpeza de cache, mas continuando..."
    fi
    log_success "Limpeza do sistema concluída"

    # Remover trap e limpar rollback (desinstalação bem-sucedida)
    trap - ERR
    cleanup_rollback

    log_success "Desinstalação do Docker concluída com sucesso!"
    log_warning "Recomenda-se reiniciar o sistema para completar a desinstalação"
}

# Função de pós-instalação
post_install_docker() {
    log_info "=== INICIANDO CONFIGURAÇÃO PÓS-INSTALAÇÃO DO DOCKER ==="
    check_user
    
    if ! check_docker_installed; then
        log_error "Docker não está instalado neste sistema"
        log_info "Execute './docker_setup.sh --install' como root/sudo para instalar"
        exit 1
    fi

    # Inicializar rollback para pós-instalação
    ROLLBACK_ACTIONS=()
    ROLLBACK_FILES=()
    ROLLBACK_PACKAGES=()
    
    # Trap para rollback em caso de erro
    trap 'log_error "Configuração pós-instalação falhada. Iniciando rollback..."; execute_rollback; exit 1' ERR

    # Etapa 1: Criar grupo docker (se não existir)
    log_info "Verificando grupo docker..."
    if ! getent group docker > /dev/null; then
        confirm_continue "O grupo docker não existe. Criar agora"
        sudo groupadd docker
        if ! check_error "groupadd docker"; then
            execute_rollback
            exit 1
        fi
        add_rollback_action "sudo groupdel docker 2>/dev/null || true"
        log_success "Grupo docker criado"
    else
        log_info "Grupo docker já existe"
    fi

    # Etapa 2: Adicionar usuário ao grupo docker
    local user_was_in_group=false
    if groups $USER | grep -q '\bdocker\b'; then
        user_was_in_group=true
        log_info "Usuário já está no grupo docker"
    else
        confirm_continue "Adicionar usuário $USER ao grupo docker"
        sudo usermod -aG docker $USER
        if ! check_error "usermod -aG docker"; then
            execute_rollback
            exit 1
        fi
        add_rollback_action "sudo gpasswd -d $USER docker 2>/dev/null || true"
        log_success "Usuário $USER adicionado ao grupo docker"
        
        log_warning "É necessário fazer logout/login ou reiniciar para que as alterações tenham efeito"
        confirm_continue "Deseja aplicar as alterações imediatamente com 'newgrp docker'"
        if ! newgrp docker; then
            log_warning "Falha ao aplicar 'newgrp docker', mas continuando..."
        fi
    fi

    # Etapa 3: Verificar se o serviço Docker está rodando
    if ! systemctl is-active --quiet docker; then
        log_info "Iniciando serviço Docker..."
        sudo systemctl start docker
        if ! check_error "systemctl start docker"; then
            execute_rollback
            exit 1
        fi
        sleep 3
    fi

    # Etapa 4: Verificar permissões
    confirm_continue "Verificar permissões do Docker sem sudo"
    log_info "Executando 'docker run hello-world'..."
    
    # Primeira tentativa
    if ! docker run --rm hello-world 2>/dev/null; then
        log_warning "Falha ao executar Docker sem sudo"
        
        # Etapa 4.1: Corrigir permissões do diretório .docker
        if [ -d "$HOME/.docker" ]; then
            confirm_continue "Corrigir permissões do diretório .docker"
            
            # Backup das permissões atuais
            local current_owner=$(stat -c '%U:%G' "$HOME/.docker" 2>/dev/null || echo "")
            if [ -n "$current_owner" ]; then
                add_rollback_action "sudo chown $current_owner '$HOME/.docker' -R 2>/dev/null || true"
            fi
            
            sudo chown "$USER":"$USER" "$HOME/.docker" -R
            sudo chmod g+rwx "$HOME/.docker" -R
            if ! check_error "chmod/chown .docker"; then
                execute_rollback
                exit 1
            fi
            log_success "Permissões do diretório .docker corrigidas"
            
            log_info "Tentando novamente..."
            if ! docker run --rm hello-world; then
                log_error "Ainda não é possível executar Docker sem sudo"
                execute_rollback
                exit 1
            fi
        else
            log_error "Não foi possível executar Docker sem sudo"
            execute_rollback
            exit 1
        fi
    fi
    log_success "Docker funciona sem sudo"

    # Etapa 5: Configurar inicialização automática
    confirm_continue "Configurar Docker para iniciar automaticamente com o sistema"
    log_info "Habilitando serviços Docker..."
    
    sudo systemctl enable docker.service
    if ! check_error "systemctl enable docker.service"; then
        execute_rollback
        exit 1
    fi
    add_rollback_action "sudo systemctl disable docker.service 2>/dev/null || true"
    
    sudo systemctl enable containerd.service
    if ! check_error "systemctl enable containerd.service"; then
        execute_rollback
        exit 1
    fi
    add_rollback_action "sudo systemctl disable containerd.service 2>/dev/null || true"
    
    log_success "Serviços Docker configurados para iniciar automaticamente"

    # Etapa 6: Verificar status
    log_info "Verificando status do Docker..."
    systemctl status docker.service --no-pager --lines=5 || true
    log_info "Verificando status do containerd..."
    systemctl status containerd.service --no-pager --lines=5 || true

    # Remover trap e limpar rollback (configuração bem-sucedida)
    trap - ERR
    cleanup_rollback

    log_success "Configuração pós-instalação concluída com sucesso!"
    
    if [ "$user_was_in_group" = false ]; then
        log_warning "IMPORTANTE: Você foi adicionado ao grupo docker."
        log_warning "Para que as alterações tenham efeito completo, faça logout e login novamente,"
        log_warning "ou reinicie o sistema."
    fi
    
    log_info "Docker está pronto para uso!"
}
        log_warning "É necessário fazer logout/login ou reiniciar para que as alterações tenham efeito"
        confirm_continue "Deseja aplicar as alterações imediatamente com 'newgrp docker'"
        newgrp docker
        check_error "newgrp docker"
    else
        log_info "Usuário já está no grupo docker"
    fi

    # Etapa 3: Verificar permissões
    confirm_continue "Verificar permissões do Docker sem sudo"
    log_info "Executando 'docker run hello-world'..."
    docker run --rm hello-world
    if [ $? -ne 0 ]; then
        log_warning "Falha ao executar Docker sem sudo"
        
        # Etapa 3.1: Corrigir permissões do diretório .docker
        if [ -d "$HOME/.docker" ]; then
            confirm_continue "Corrigir permissões do diretório .docker"
            sudo chown "$USER":"$USER" "$HOME/.docker" -R
            sudo chmod g+rwx "$HOME/.docker" -R
            check_error "chmod/chown .docker"
            log_success "Permissões do diretório .docker corrigidas"
            
            log_info "Tentando novamente..."
            docker run --rm hello-world
            check_error "docker run hello-world (segunda tentativa)"
        fi
    fi
    log_success "Docker funciona sem sudo"

    # Etapa 4: Configurar inicialização automática
    confirm_continue "Configurar Docker para iniciar automaticamente com o sistema"
    log_info "Habilitando serviços Docker..."
    sudo systemctl enable docker.service
    check_error "systemctl enable docker.service"
    sudo systemctl enable containerd.service
    check_error "systemctl enable containerd.service"
    log_success "Serviços Docker configurados para iniciar automaticamente"

    # Etapa 5: Verificar status
    log_info "Verificando status do Docker..."
    systemctl status docker.service --no-pager
    log_info "Verificando status do containerd..."
    systemctl status containerd.service --no-pager

    log_success "Configuração pós-instalação concluída com sucesso!"
    log_warning "Se ainda encontrar problemas, recomenda-se reiniciar o sistema"
}

# Função de ajuda
show_help() {
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo "Compatível com Ubuntu 24.04 LTS"
    echo ""
    echo "Uso: $0 [OPÇÃO]"
    echo ""
    echo "Opções:"
    echo "  --install       Instala o Docker CE (requer root/sudo)"
    echo "  --uninstall     Remove completamente o Docker (requer root/sudo)"
    echo "  --post-install  Configura Docker para usuário normal (sem root/sudo)"
    echo "  --status        Mostra status atual do Docker"
    echo "  --info          Mostra informações detalhadas de uso"
    echo "  --version       Mostra versão do script"
    echo "  --help          Mostra esta ajuda"
    echo ""
    echo "Exemplos:"
    echo "  sudo $0 --install"
    echo "  sudo $0 --uninstall"
    echo "  $0 --post-install"
    echo ""
}

# Função de informações detalhadas (manual)
show_info() {
    cat << 'EOF'
================================================================================
                    DOCKER SETUP SCRIPT - MANUAL DE USO
================================================================================

NOME
    docker_setup.sh - Script automatizado para gerenciamento do Docker

SINOPSE
    docker_setup.sh [OPÇÃO]

DESCRIÇÃO
    Este script automatiza a instalação, configuração e desinstalação do Docker
    CE no Ubuntu 24.04 LTS. Inclui funcionalidades de rollback e verificação de
    conectividade para maior segurança e confiabilidade.

FUNCIONALIDADES
    ✓ Verificação automática de compatibilidade do sistema
    ✓ Verificação de conectividade antes de downloads
    ✓ Sistema completo de rollback em caso de falhas
    ✓ Backup automático durante desinstalação
    ✓ Configuração automática de usuários
    ✓ Logs detalhados de todas as operações

OPÇÕES
    --install
        Instala o Docker CE e todos os componentes necessários.
        Requer privilégios de root/sudo.
        
        Processo:
        • Remove pacotes conflitantes
        • Adiciona repositório oficial do Docker
        • Instala Docker CE, CLI e plugins
        • Verifica instalação com hello-world
        • Configura usuário (opcional)

    --uninstall
        Remove completamente o Docker do sistema.
        Requer privilégios de root/sudo.
        
        Processo:
        • Para todos os serviços Docker
        • Oferece backup dos dados (opcional)
        • Remove todos os pacotes Docker
        • Remove dados persistentes (imagens, containers, volumes)
        • Remove configurações e repositórios
        • Executa limpeza do sistema

    --post-install
        Configura o Docker para uso sem sudo.
        Deve ser executado como usuário normal.
        
        Processo:
        • Cria grupo docker (se necessário)
        • Adiciona usuário atual ao grupo docker
        • Corrige permissões do diretório ~/.docker
        • Configura inicialização automática
        • Testa funcionamento sem sudo

    --status
        Exibe informações sobre o estado atual do Docker:
        • Versão instalada
        • Status do serviço
        • Configuração do usuário atual

    --info
        Exibe este manual de uso completo.

    --version
        Mostra a versão atual do script.

    --help
        Exibe ajuda resumida com opções disponíveis.

EXEMPLOS DE USO
    # Instalação completa do Docker
    sudo ./docker_setup.sh --install

    # Configuração pós-instalação para usuário atual
    ./docker_setup.sh --post-install

    # Verificar status do Docker
    ./docker_setup.sh --status

    # Desinstalar completamente o Docker
    sudo ./docker_setup.sh --uninstall

SISTEMA DE ROLLBACK
    O script inclui um sistema robusto de rollback que:
    • Monitora todas as alterações durante a execução
    • Cria backups automáticos de arquivos modificados
    • Registra pacotes instalados/removidos
    • Executa rollback automático em caso de falha
    • Permite recuperação manual se necessário

VERIFICAÇÃO DE CONECTIVIDADE
    Antes de qualquer download, o script verifica:
    • Conectividade com DNS público (8.8.8.8)
    • Acesso ao repositório Docker (download.docker.com)
    • Acesso aos repositórios Ubuntu (archive.ubuntu.com)

LOGS E DEPURAÇÃO
    O script produz logs detalhados usando:
    [INFO]     - Informações gerais
    [SUCCESS]  - Operações concluídas com sucesso
    [WARNING]  - Avisos importantes
    [ERROR]    - Erros que requerem atenção

REQUISITOS DO SISTEMA
    • Ubuntu 24.04 LTS (recomendado)
    • Outras versões do Ubuntu (com confirmação)
    • Conexão com a internet
    • Privilégios sudo para instalação/desinstalação

ARQUIVOS MODIFICADOS
    O script pode modificar/criar os seguintes arquivos:
    • /etc/apt/sources.list.d/docker.list
    • /etc/apt/keyrings/docker.asc
    • /etc/apt/keyrings/ (diretório)
    • /var/lib/docker/ (dados do Docker)
    • /var/lib/containerd/ (dados do containerd)
    • ~/.docker/ (configurações do usuário)

SOLUÇÃO DE PROBLEMAS
    1. Erro de conectividade:
       • Verifique sua conexão com a internet
       • Teste: ping 8.8.8.8

    2. Docker não funciona sem sudo:
       • Execute: ./docker_setup.sh --post-install
       • Faça logout/login após adicionar ao grupo docker

    3. Falha na instalação:
       • O rollback é executado automaticamente
       • Verifique os logs para identificar o problema
       • Tente novamente após resolver o problema

    4. Serviço não inicia:
       • sudo systemctl start docker
       • sudo systemctl status docker

SEGURANÇA
    • O script verifica permissões antes de executar operações
    • Solicita confirmação para operações destrutivas
    • Nunca executa comandos sem validação prévia
    • Cria backups antes de modificações importantes

SUPORTE
    Para problemas ou sugestões:
    • Verifique os logs detalhados do script
    • Consulte a documentação oficial do Docker
    • Execute com --status para diagnóstico

VERSÃO
    Script versão 2.1.0
    Compatível com Docker CE e Ubuntu 24.04 LTS

AUTOR
    Sistema de Automação Docker
    
================================================================================
EOF
}

# Função para mostrar versão
show_version() {
    echo "$SCRIPT_NAME"
    echo "Versão: $SCRIPT_VERSION"
    echo "Compatibilidade: Ubuntu 24.04 LTS"
    echo "Suporte Docker: CE (Community Edition)"
    echo "Data de compilação: $(date +%Y-%m-%d)"
}

# Função para mostrar status do Docker
show_status() {
    log_info "=== STATUS DO DOCKER ==="
    
    if check_docker_installed; then
        log_success "Docker está instalado"
        docker --version
        echo ""
        
        if systemctl is-active --quiet docker; then
            log_success "Serviço Docker está ativo"
        else
            log_warning "Serviço Docker não está ativo"
        fi
        
        if groups $USER | grep -q '\bdocker\b' 2>/dev/null; then
            log_success "Usuário atual está no grupo docker"
        else
            log_warning "Usuário atual NÃO está no grupo docker"
        fi
    else
        log_warning "Docker não está instalado"
    fi
}

# Main
main() {
    # Verificar versão do Ubuntu primeiro
    check_ubuntu_version
    
    case "$1" in
        --install)
            install_docker
            ;;
        --uninstall)
            uninstall_docker
            ;;
        --post-install)
            post_install_docker
            ;;
        --status)
            show_status
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Docker Setup Script - Ubuntu 24.04 LTS"
            echo ""
            show_status
            echo ""
            echo "Para ver todas as opções disponíveis, execute:"
            echo "$0 --help"
            ;;
    esac
}

# Executar função principal com os argumentos
main "$@"
