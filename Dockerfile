
Save New Duplicate & Edit Just Text Twitter
# Install any file auto save the root file evey rest same file
# Connect to Google drive that save all data and backup all data and every rest same data

The VPS is 24/7 

name: MoonLink VPS

on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
  workflow_dispatch:

jobs:
  vps-session:
    runs-on: ubuntu-22.04
    timeout-minutes: 350  # Just under 6 hours

    env:
      VPS_USERNAME: ${{ secrets.VPS_USERNAME || 'root' }}
      VPS_PASSWORD: ${{ secrets.VPS_PASSWORD || 'root' }}
      HOSTNAME: ${{ secrets.HOSTNAME || 'MoonLinkVPS' }}
      TAILNET_NAME: ${{ secrets.TAILNET_NAME || 'itsgamer2o24.github' }}
      TAILSCALE_AUTHKEY: ${{ secrets.TAILSCALE_AUTHKEY || 'tskey-auth-kENZY6pVkB11CNTRL-jBUsfthhXgfb7ZYoBb1Phf3VYeZ6zTdv' }}
      TAILSCALE_APIKEY: ${{ secrets.TAILSCALE_APIKEY  || 'tskey-api-kfo58A6Srz11CNTRL-6pbT7HEmm5YLP93THfzY5YUXyfEmnDwnY' }}

    steps:
      - name: Checkout repo
        uses: actions/checkout@v4

      - name: Set hostname from env
        run: sudo hostnamectl set-hostname ${{ env.HOSTNAME }}

      - name: Create backup directory
        run: mkdir -p ./backup

      - name: Download VPS backup (if any)
        uses: actions/download-artifact@v4
        with:
          name: vps-backup
          path: ./backup
        continue-on-error: true

      - name: Install prerequisites
        run: |
          sudo apt update
          sudo apt install -y curl unzip sudo net-tools neofetch rsync qrencode sshpass

      - name: Install Tailscale official script
        run: |
          curl -fsSL https://tailscale.com/install.sh | sh

      - name: Restore backup files to root
        run: |
          if [ -f ./backup/root-backup.tar.gz ]; then
            echo "Restoring root directory backup..."
            sudo tar -xzf ./backup/root-backup.tar.gz -C / 2>/dev/null || echo "Backup restore completed with some warnings"
            echo "Root backup restored successfully"
          else
            echo "No root backup found, starting fresh"
          fi

      - name: Restore Tailscale state
        run: |
          if [ -f ./backup/tailscaled.state ]; then
            sudo mkdir -p /var/lib/tailscale
            sudo cp ./backup/tailscaled.state /var/lib/tailscale/tailscaled.state
            sudo chmod 600 /var/lib/tailscale/tailscaled.state
            echo "Tailscale state restored"
          else
            echo "No Tailscale state found, will create new connection"
          fi

      - name: Start Tailscale
        run: |
          sudo tailscaled &
          sleep 8
          sudo tailscale up --authkey ${{ secrets.TAILSCALE_AUTHKEY }} --hostname=${{ env.HOSTNAME }} || echo "Tailscale already up"

      - name: Create user, enable root SSH, and save SSH info
        run: |
          echo "::add-mask::${{ env.VPS_PASSWORD }}"
          USERNAME="${{ env.VPS_USERNAME }}"
          PASSWORD="${{ env.VPS_PASSWORD }}"

          # Create or update custom user
          if ! id -u "$USERNAME" >/dev/null 2>&1; then
            sudo useradd -m -s /bin/bash "$USERNAME"
            echo "$USERNAME:$PASSWORD" | sudo chpasswd
            sudo usermod -aG sudo "$USERNAME"
            echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/"$USERNAME"
            echo "Created user: $USERNAME with password from environment"
          else
            echo "User $USERNAME already exists, updating password"
            echo "$USERNAME:$PASSWORD" | sudo chpasswd
          fi

          # Set password for root account
          echo "root:$PASSWORD" | sudo chpasswd
          echo "Root password updated"

          # Enable root SSH login
          sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
          sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
          sudo systemctl restart ssh || sudo systemctl restart sshd

          # Save SSH connection info to file
          mkdir -p ./ssh-info
          TS_IP=$(tailscale ip -4 | head -n1 || true)

          {
            echo "===== VPS SSH INFO ====="
            echo "Tailscale IP: $TS_IP"
            echo "-----------------------"
            echo "👉 Root login:"
            echo "ssh root@$TS_IP"
            echo "Password: $PASSWORD"
            echo ""
            echo "👉 User login:"
            echo "ssh $USERNAME@$TS_IP"
            echo "Password: $PASSWORD"
            echo ""
            echo "👉 One-liner with sshpass:"
            echo "sshpass -p '$PASSWORD' ssh -o StrictHostKeyChecking=no root@$TS_IP"
            echo "sshpass -p '$PASSWORD' ssh -o StrictHostKeyChecking=no $USERNAME@$TS_IP"
            echo "========================"
          } > ./ssh-info/ssh-info.txt

      - name: Print SSH + Tailscale QR codes
        run: |
          TS_IP=$(tailscale ip -4 | head -n1 || true)
          PASSWORD="${{ env.VPS_PASSWORD }}"

          mkdir -p ./ssh-qr

          echo "📱 Root QR (auto-login):"
          qrencode -t ANSIUTF8 "sshpass -p '$PASSWORD' ssh -o StrictHostKeyChecking=no root@$TS_IP"
          qrencode -o ./ssh-qr/root-ssh.png "sshpass -p '$PASSWORD' ssh -o StrictHostKeyChecking=no root@$TS_IP"

          echo ""
          echo "📱 User QR (auto-login):"
          qrencode -t ANSIUTF8 "sshpass -p '$PASSWORD' ssh -o StrictHostKeyChecking=no ${{ env.VPS_USERNAME }}@$TS_IP"
          qrencode -o ./ssh-qr/user-ssh.png "sshpass -p '$PASSWORD' ssh -o StrictHostKeyChecking=no ${{ env.VPS_USERNAME }}@$TS_IP"

          echo ""
          echo "🌐 Tailscale Web Login QR:"
          qrencode -t ANSIUTF8 "https://login.tailscale.com/admin/machines"
          qrencode -o ./ssh-qr/tailscale-login.png "https://login.tailscale.com/admin/machines"

      - name: Upload SSH info artifact
        uses: actions/upload-artifact@v4
        with:
          name: ssh-info
          path: ./ssh-info/ssh-info.txt
          retention-days: 3

      - name: Upload SSH QR artifact
        uses: actions/upload-artifact@v4
        with:
          name: ssh-qr
          path: ./ssh-qr/
          retention-days: 3

      - name: Start auto-save script
        run: |
          sudo tee /root/auto-save.sh > /dev/null << 'EOF'
          #!/bin/bash
          BACKUP_DIR="/tmp/auto-backup"
          LOG_FILE="/var/log/auto-save.log"
          
          echo "$(date): Auto-save script started" >> $LOG_FILE
          
          while true; do
            sleep 1800  # 30 minutes (1800 seconds)
            echo "$(date): Starting auto-save..." >> $LOG_FILE
            
            # Create backup directory
            mkdir -p $BACKUP_DIR
            
            # Create backup with error handling
            if tar --exclude='/proc' \
                --exclude='/sys' \
                --exclude='/dev' \
                --exclude='/run' \
                --exclude='/tmp' \
                --exclude='/var/cache' \
                --exclude='/var/log' \
                --exclude='/var/tmp' \
                --exclude='/boot' \
                --exclude='/lib/modules' \
                --exclude='/usr/lib/modules' \
                --exclude='/snap' \
                --exclude='/mnt' \
                --exclude='/media' \
                -czf $BACKUP_DIR/root-auto-save.tar.gz \
                /root /home /etc /opt /var/lib/tailscale 2>>$LOG_FILE; then
              echo "$(date): Auto-save completed successfully" >> $LOG_FILE
            else
              echo "$(date): Auto-save completed with warnings" >> $LOG_FILE
            fi
          done
          EOF
          sudo chmod +x /root/auto-save.sh
          sudo nohup /root/auto-save.sh &

      - name: Sleep to keep VPS alive
        run: sleep 21600  # 6 hours

      - name: Final backup before shutdown
        run: |
          echo "Creating final backup before shutdown..."
          
          # Stop auto-save script
          sudo pkill -f auto-save.sh || true
          sleep 5
          
          # Create final backup directory
          mkdir -p ./backup
          
          # Create final backup
          echo "Starting final backup process..."
          if sudo tar --exclude='/proc' \
              --exclude='/sys' \
              --exclude='/dev' \
              --exclude='/run' \
              --exclude='/tmp' \
              --exclude='/var/cache' \
              --exclude='/var/log' \
              --exclude='/var/tmp' \
              --exclude='/boot' \
              --exclude='/lib/modules' \
              --exclude='/usr/lib/modules' \
              --exclude='/snap' \
              --exclude='/mnt' \
              --exclude='/media' \
              -czf ./backup/root-backup.tar.gz \
              /root /home /etc /opt 2>/dev/null; then
            echo "Final backup created successfully"
          else
            echo "Final backup completed with some warnings"
          fi
          
          # Backup Tailscale state
          if [ -f /var/lib/tailscale/tailscaled.state ]; then
            sudo cp /var/lib/tailscale/tailscaled.state ./backup/
            echo "Tailscale state backed up"
          else
            echo "No Tailscale state to backup"
          fi
          
          # Fix permissions
          sudo chown -R $USER:$USER ./backup/ 2>/dev/null || true
          
          # Verify backup files exist
          if [ -f ./backup/root-backup.tar.gz ]; then
            BACKUP_SIZE=$(du -h ./backup/root-backup.tar.gz | cut -f1)
            echo "Final backup completed - Size: $BACKUP_SIZE"
          else
            echo "Warning: Final backup file not found!"
          fi

      - name: Upload VPS backup artifact
        uses: actions/upload-artifact@v4
        with:
          name: vps-backup
          path: ./backup/
          retention-days: 30
