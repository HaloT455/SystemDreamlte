# ALICE SYSTEM — Samsung Galaxy S8+ (dream2lte)

Kho lưu **cây tệp SYSTEM** của bản Android 16 / One UI 8 có Samsung Camera + Video6 đã chạy được trên thiết bị ALICE.

> **Trạng thái:** repository mới được khởi tạo. **Chưa có nội dung SYSTEM V2 trên GitHub**. Các file SYSTEM V2 đang ở SSD của Zorin OS và phải được trích xuất, kiểm tra rồi đẩy lên từ Zorin.

## Các nhánh dự kiến

- `main`: hướng dẫn, công cụ và tài liệu an toàn.
- `baseline/system-v2-camera`: ảnh chụp cây tệp của SYSTEM V2 đã được người dùng xác nhận hoạt động, giữ làm **baseline**, không thử nghiệm trực tiếp trên nhánh này.
- `work/a16-radio-raf0`: nghiên cứu sửa RadioCapability/Viettel LTE trên bản sao, **chỉ tạo sau khi baseline được đưa lên thành công**.

SYSTEM V1 gốc `/mnt/alice-ssd/ALICE_SYSTEM/BASE/system_original.img` không dùng làm nguồn V2 và không chỉnh sửa.

## Đưa SYSTEM V2 lên từ Zorin

Công cụ: [`tools/publish_system_v2_from_zorin.sh`](tools/publish_system_v2_from_zorin.sh).

Cần:
- Ảnh **SYSTEM V2 đúng bản đang có Samsung Camera hoạt động** (xác minh bằng nội dung và checksum; đường dẫn mặc định `/mnt/alice-ssd/ALICE_SYSTEM/OUTPUT/system_alice_camera_v2.img` chỉ là gợi ý chưa xác minh).
- Zorin có `git`, `git-lfs`, `rsync`, hỗ trợ EROFS và quyền để mount read-only.
- GitHub đã cấu hình quyền `git push`; **không nhập PAT vào lệnh hoặc đưa token lên repo**.
- Đủ dung lượng trống cho cây tệp giải nén + Git staging (có thể nhiều GB). GitHub LFS có giới hạn dung lượng/lưu lượng theo tài khoản.
- Xác nhận **có quyền chia sẻ** các thành phần Samsung/Google độc quyền nếu repo public. Có thể chuyển repo thành private trước khi tải lên.

Ảnh `system.img` nguyên khối không được đưa vào Git; chỉ đẩy cây tệp đã giải nén. Git không lưu đầy đủ uid/gid, SELinux xattr và hardlinks: công cụ xuất manifest metadata tách riêng phục vụ dựng lại EROFS, nhưng **không bảo đảm tái tạo byte-identical**.

## Zorin OS: chạy công cụ đã có trong repo

**Kiểm tra file SYSTEM V2 trên SSD (không upload):**

```bash
git clone https://github.com/HaloT455/SystemDreamlte.git ~/SystemDreamlte-setup
cd ~/SystemDreamlte-setup
bash tools/publish_system_v2_from_zorin.sh /mnt/alice-ssd/ALICE_SYSTEM/OUTPUT/system_alice_camera_v2.img inspect
```

Nếu không thấy `system_alice_camera_v2.img`, công cụ hiện danh sách ảnh ứng viên; chọn **đúng bản SYSTEM V2 đã thử và Camera hoạt động**, không chọn SYSTEM V1.

**Xuất nội dung và push lên nhánh riêng (chỉ khi đã xác nhận quyền chia sẻ OEM / Google vì repo hiện PUBLIC):**

```bash
sudo apt update
sudo apt install -y git git-lfs rsync file
cd ~/SystemDreamlte-setup
ALICE_CONFIRM_PUBLIC_PUBLISH=YES bash tools/publish_system_v2_from_zorin.sh /mnt/alice-ssd/ALICE_SYSTEM/OUTPUT/system_alice_camera_v2.img publish
```

Bản SYSTEM V2 đầu vào chỉ được mount read-only; Git checkout nằm ở `/mnt/alice-ssd/ALICE_SYSTEM/GITHUB_SYSTEM_V2_IMPORT/SystemDreamlte`. Nếu đẩy GitHub thất bại do tài khoản, kết nối hay Git LFS quota, **không chạy lại toàn bộ script lên cùng checkout**; chỉnh lý rồi đẩy lại tại checkout:

```bash
cd /mnt/alice-ssd/ALICE_SYSTEM/GITHUB_SYSTEM_V2_IMPORT/SystemDreamlte
git push -u origin baseline/system-v2-camera
```

### Giới hạn quan trọng
- Repo công khai có thể vi phạm quyền phát hành lại phần mềm độc quyền. Nên chuyển `SystemDreamlte` sang **private** trước khi xuất toàn bộ SYSTEM; kể cả private vẫn cần tuân thủ giấy phép.
- Source tree là **các tệp được giải nén từ image**, không phải mã nguồn Java/C/C++ của Samsung.
- File `metadata/system-v2-fs.json` giữ thông tin uid/gid, SELinux và hardlink; cần tooling EROFS riêng để dựng lại chính xác.
- Không sửa image gốc và không tải nguyên `system.img` lên Git.
- Nếu GitHub LFS báo hết quota hoặc file vượt giới hạn, phải xử lý quota/nhóm dữ liệu phù hợp; đừng force-push hay bỏ kiểm tra integrity.
