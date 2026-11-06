# Layihənin izahı (müsahibəyə hazırlıq)

## Bir cümlə ilə

İki Kubernetes klasterini (dev və prod) Git üzərindən idarə edirəm: dev özü yenilənir və əl ilə edilən dəyişiklikləri geri qaytarır, prod isə yalnız icazəli şəxs təsdiqləyəndə dəyişir. Argo CD-nin prod-a çıxışı bir namespace ilə məhdudlaşdırılıb.

## Əsas anlayışlar

**GitOps** — klasterdə nə işləməli olduğu Git-də yazılır. Heç kim `kubectl apply` ilə əl ilə dəyişiklik etmir. Dəyişiklik istəyirsənsə, Git-də Pull Request açırsan, review olunur, birləşir, sistem özü tətbiq edir. Üstünlüyü: hər dəyişikliyin tarixçəsi, müəllifi və təsdiqi var, geri qaytarmaq bir `git revert`-dir.

**Argo CD** — GitOps-u həyata keçirən alət. Git-ə baxır, klasterə baxır, fərq varsa göstərir və ya düzəldir.

- **Synced / OutOfSync** — klaster Git ilə eynidirmi, yoxsa fərq var.
- **Healthy** — pod-lar həqiqətən işləyirmi.
- **Auto-sync** — Git dəyişən kimi avtomatik tətbiq et.
- **Self-heal** — kimsə klasterdə əl ilə nəyisə dəyişsə, Git-dəki halına qaytar.
- **Drift** — klasterin Git-dən fərqlənməsi.

**Application** — Argo CD-yə "bu Git qovluğunu bu klasterin bu namespace-inə yerləşdir" deyən obyekt.

**ApplicationSet** — bir şablondan çoxlu Application yaradır. Bizdə bir şablon iki mühit üçün iki Application yaradır.

**AppProject** — tətbiqlərin nəyə icazəsi olduğunu təyin edən çərçivə: hansı Git repo-dan, hansı klasterə, hansı namespace-ə, hansı növ obyekt. Git-ə yazma icazəsi olan biri belə bu çərçivədən çıxa bilməz.

**Kustomize** — eyni YAML-dan fərqli mühitlər üçün versiya yaratmaq. `base` ortaq hissədir, `overlays/dev` və `overlays/prod` yalnız fərqləri yazır (replika sayı, image tag, PDB).

**PodDisruptionBudget (PDB)** — node yenilənəndə və ya söndürüləndə eyni anda neçə pod-un dayana biləcəyini məhdudlaşdırır. Prod-da həmişə ən azı 2 API pod-u işləyir.

## Təhlükəsizlik baxımından ən vacib iki məqam

1. **Argo CD prod-da cluster-admin deyil.** Standart qurulumda Argo CD-yə hər şeyə icazə verilir. Biz ona yalnız bir namespace-də, yalnız lazım olan obyekt növləri üçün icazə verdik. Test bunu yoxlayır: Argo CD-nin açarı ilə secret oxumaq, `kube-system`-ə girmək, ClusterRoleBinding yaratmaq mümkün deyil. Argo CD ələ keçirilsə, zərər bir namespace ilə məhdud qalır.

2. **Guardrail testləri.** Bilərəkdən "pis" Application-lar yaradırıq: `kube-system`-ə deploy, naməlum repo-dan deploy, içində ClusterRole və Secret olan tətbiq. Argo CD hamısını rədd edir və klasterdə heç nə yaranmır.

## Yol boyu tapılan problem

Birinci CI işində prod sinxronlaşmadı. Səbəb: Argo CD namespace-dəki bütün resurs növlərini (Secret, PVC və s.) siyahılamağa çalışır, bizim sıx icazələr isə buna imkan vermirdi. İcazələri genişləndirmək asan yol olardı, amma təhlükəsizliyi zəiflədərdi. Bunun əvəzinə Argo CD-yə yalnız idarə etdiyimiz növləri izləməyi dedik (`resource.inclusions`). Müsahibədə "least privilege-i saxlamaq üçün nə vaxtsa çətinliklə üzləşmisən?" sualına yaxşı cavabdır.

## Ehtimal olunan suallar

- **Niyə prod-da auto-sync yoxdur?** Prod dəyişiklikləri təsdiq tələb edir. Drift görünür, amma insan qərar verir: bəlkə əl ilə edilən dəyişiklik təcili düzəlişdir və Git-ə də əlavə olunmalıdır.
- **Image-i prod-a necə çıxarırsan (promotion)?** `overlays/prod/kustomization.yaml`-da `newTag`-i dəyişən Pull Request açılır, review olunur, birləşir, release manager sync edir.
- **Secret-lər necə?** Bu layihədə Git-ə düşmür, platforma komandası ayrıca idarə edir. Növbəti addım Sealed Secrets və ya External Secrets Operator olardı.
- **Rancher niyə yoxdur?** Giriş nəzarətini Argo CD-nin AppProject və RBAC-ı ilə qurdum. Rancher klasterləri idarə etmək üçün UI və mərkəzləşdirilmiş istifadəçi idarəetməsi verir; prinsip eynidir.
