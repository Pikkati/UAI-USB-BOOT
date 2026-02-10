#!/bin/bash
set -euo pipefail

echo "🎯 Careful USB Multi-Boot Build"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Configuration:"
echo "   Device: /dev/sdb (28.9GB USB DISK 2.0)"
echo "   Mode: Conservative - Only use available ISOs"
echo "   ISOs: Ubuntu Desktop, Ubuntu Server, Kali Linux"
echo ""
echo "⚠️  CRITICAL WARNING:"
echo "   This will COMPLETELY ERASE /dev/sdb"
echo "   All data on the USB drive will be lost"
echo "   Double-check this is your target device!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check available ISOs
echo "📦 Checking available ISOs:"
echo ""

AVAILABLE_ISOS=()
if [ -f "$HOME/Downloads/ubuntu-24.04.3-desktop-amd64.iso" ]; then
    SIZE=$(stat -c%s "$HOME/Downloads/ubuntu-24.04.3-desktop-amd64.iso" | awk '{print int($1/1024/1024)"MB"}')
    echo "✅ Ubuntu Desktop 24.04.3: $SIZE"
    AVAILABLE_ISOS+=("ubuntu-desktop:lts")
else
    echo "❌ Ubuntu Desktop 24.04.3: Not found"
fi

if [ -f "$HOME/Downloads/ubuntu-24.04.3-live-server-amd64.iso" ]; then
    SIZE=$(stat -c%s "$HOME/Downloads/ubuntu-24.04.3-live-server-amd64.iso" | awk '{print int($1/1024/1024)"MB"}')
    echo "✅ Ubuntu Server 24.04.3: $SIZE"
    AVAILABLE_ISOS+=("ubuntu-server:lts")
else
    echo "❌ Ubuntu Server 24.04.3: Not found"
fi

if [ -f "$HOME/Downloads/kali-linux-2025.1-installer-amd64.iso" ]; then
    SIZE=$(stat -c%s "$HOME/Downloads/kali-linux-2025.1-installer-amd64.iso" | awk '{print int($1/1024/1024)"MB"}')
    echo "✅ Kali Linux 2025.1: $SIZE"
    AVAILABLE_ISOS+=("kali-linux:lts")
else
    echo "❌ Kali Linux 2025.1: Not found"
fi

echo ""
echo "📊 Build Plan:"
echo "   Will write ${#AVAILABLE_ISOS[@]} distributions"
echo "   Total estimated size: ~8GB"
echo "   Expected time: 10-20 minutes"
echo ""

# Final confirmation
echo "🔴 FINAL CONFIRMATION REQUIRED"
echo ""
read -p "Type 'ERASE /dev/sdb' to confirm: " confirm
if [ "$confirm" != "ERASE /dev/sdb" ] && [ "$confirm" != "ERASE" ]; then
    echo "❌ Operation cancelled by user"
    exit 1
fi

echo ""
echo "🚀 Starting build process..."
echo ""

# Build the command
DIST_ARGS=""
for distro in "${AVAILABLE_ISOS[@]}"; do
    DIST_ARGS="$DIST_ARGS -i $distro"
done

echo "Command: sudo bash ./usb-pro-builder.sh -d /dev/sdb $DIST_ARGS -y"
echo ""

# Execute the build
sudo bash ./usb-pro-builder.sh -d /dev/sdb $DIST_ARGS -y

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ USB Multi-Boot Build Complete!"
echo ""
echo "🎯 Your USB now contains:"
for distro in "${AVAILABLE_ISOS[@]}"; do
    echo "   • ${distro%%:*} (${distro##*:} version)"
done
echo ""
echo "💡 Boot from USB to access the GRUB menu"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
