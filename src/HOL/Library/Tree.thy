(* Author: Tobias Nipkow *)
(* Todo: minimal ipl of balanced trees *)

section \<open>Binary Tree\<close>

theory Tree
imports Main
begin

datatype 'a tree =
  Leaf ("\<langle>\<rangle>") |
  Node "'a tree" (root_val: 'a) "'a tree" ("(1\<langle>_,/ _,/ _\<rangle>)")
datatype_compat tree

text\<open>Can be seen as counting the number of leaves rather than nodes:\<close>

definition size1 :: "'a tree \<Rightarrow> nat" where
"size1 t = size t + 1"

fun subtrees :: "'a tree \<Rightarrow> 'a tree set" where
"subtrees \<langle>\<rangle> = {\<langle>\<rangle>}" |
"subtrees (\<langle>l, a, r\<rangle>) = insert \<langle>l, a, r\<rangle> (subtrees l \<union> subtrees r)"

fun mirror :: "'a tree \<Rightarrow> 'a tree" where
"mirror \<langle>\<rangle> = Leaf" |
"mirror \<langle>l,x,r\<rangle> = \<langle>mirror r, x, mirror l\<rangle>"

class height = fixes height :: "'a \<Rightarrow> nat"

instantiation tree :: (type)height
begin

fun height_tree :: "'a tree => nat" where
"height Leaf = 0" |
"height (Node t1 a t2) = max (height t1) (height t2) + 1"

instance ..

end

fun min_height :: "'a tree \<Rightarrow> nat" where
"min_height Leaf = 0" |
"min_height (Node l _ r) = min (min_height l) (min_height r) + 1"

fun complete :: "'a tree \<Rightarrow> bool" where
"complete Leaf = True" |
"complete (Node l x r) = (complete l \<and> complete r \<and> height l = height r)"

definition balanced :: "'a tree \<Rightarrow> bool" where
"balanced t = (height t - min_height t \<le> 1)"

text \<open>Weight balanced:\<close>
fun wbalanced :: "'a tree \<Rightarrow> bool" where
"wbalanced Leaf = True" |
"wbalanced (Node l x r) = (abs(int(size l) - int(size r)) \<le> 1 \<and> wbalanced l \<and> wbalanced r)"

text \<open>Internal path length:\<close>
fun ipl :: "'a tree \<Rightarrow> nat" where
"ipl Leaf = 0 " |
"ipl (Node l _ r) = ipl l + size l + ipl r + size r"

fun preorder :: "'a tree \<Rightarrow> 'a list" where
"preorder \<langle>\<rangle> = []" |
"preorder \<langle>l, x, r\<rangle> = x # preorder l @ preorder r"

fun inorder :: "'a tree \<Rightarrow> 'a list" where
"inorder \<langle>\<rangle> = []" |
"inorder \<langle>l, x, r\<rangle> = inorder l @ [x] @ inorder r"

text\<open>A linear version avoiding append:\<close>
fun inorder2 :: "'a tree \<Rightarrow> 'a list \<Rightarrow> 'a list" where
"inorder2 \<langle>\<rangle> xs = xs" |
"inorder2 \<langle>l, x, r\<rangle> xs = inorder2 l (x # inorder2 r xs)"

fun postorder :: "'a tree \<Rightarrow> 'a list" where
"postorder \<langle>\<rangle> = []" |
"postorder \<langle>l, x, r\<rangle> = postorder l @ postorder r @ [x]"

text\<open>Binary Search Tree:\<close>
fun bst_wrt :: "('a \<Rightarrow> 'a \<Rightarrow> bool) \<Rightarrow> 'a tree \<Rightarrow> bool" where
"bst_wrt P \<langle>\<rangle> \<longleftrightarrow> True" |
"bst_wrt P \<langle>l, a, r\<rangle> \<longleftrightarrow>
 bst_wrt P l \<and> bst_wrt P r \<and> (\<forall>x\<in>set_tree l. P x a) \<and> (\<forall>x\<in>set_tree r. P a x)"

abbreviation bst :: "('a::linorder) tree \<Rightarrow> bool" where
"bst \<equiv> bst_wrt (<)"

fun (in linorder) heap :: "'a tree \<Rightarrow> bool" where
"heap Leaf = True" |
"heap (Node l m r) =
  (heap l \<and> heap r \<and> (\<forall>x \<in> set_tree l \<union> set_tree r. m \<le> x))"


subsection \<open>@{const map_tree}\<close>

lemma eq_map_tree_Leaf[simp]: "map_tree f t = Leaf \<longleftrightarrow> t = Leaf"
by (rule tree.map_disc_iff)

lemma eq_Leaf_map_tree[simp]: "Leaf = map_tree f t \<longleftrightarrow> t = Leaf"
by (cases t) auto


subsection \<open>@{const size}\<close>

lemma size1_simps[simp]:
  "size1 \<langle>\<rangle> = 1"
  "size1 \<langle>l, x, r\<rangle> = size1 l + size1 r"
by (simp_all add: size1_def)

lemma size1_ge0[simp]: "0 < size1 t"
by (simp add: size1_def)

lemma eq_size_0[simp]: "size t = 0 \<longleftrightarrow> t = Leaf"
by(cases t) auto

lemma eq_0_size[simp]: "0 = size t \<longleftrightarrow> t = Leaf"
by(cases t) auto

lemma neq_Leaf_iff: "(t \<noteq> \<langle>\<rangle>) = (\<exists>l a r. t = \<langle>l, a, r\<rangle>)"
by (cases t) auto

lemma size_map_tree[simp]: "size (map_tree f t) = size t"
by (induction t) auto

lemma size1_map_tree[simp]: "size1 (map_tree f t) = size1 t"
by (simp add: size1_def)


subsection \<open>@{const set_tree}\<close>

lemma eq_set_tree_empty[simp]: "set_tree t = {} \<longleftrightarrow> t = Leaf"
by (cases t) auto

lemma eq_empty_set_tree[simp]: "{} = set_tree t \<longleftrightarrow> t = Leaf"
by (cases t) auto

lemma finite_set_tree[simp]: "finite(set_tree t)"
by(induction t) auto


subsection \<open>@{const subtrees}\<close>

lemma neq_subtrees_empty[simp]: "subtrees t \<noteq> {}"
by (cases t)(auto)

lemma neq_empty_subtrees[simp]: "{} \<noteq> subtrees t"
by (cases t)(auto)

lemma set_treeE: "a \<in> set_tree t \<Longrightarrow> \<exists>l r. \<langle>l, a, r\<rangle> \<in> subtrees t"
by (induction t)(auto)

lemma Node_notin_subtrees_if[simp]: "a \<notin> set_tree t \<Longrightarrow> Node l a r \<notin> subtrees t"
by (induction t) auto

lemma in_set_tree_if: "\<langle>l, a, r\<rangle> \<in> subtrees t \<Longrightarrow> a \<in> set_tree t"
by (metis Node_notin_subtrees_if)


subsection \<open>@{const height} and @{const min_height}\<close>

lemma eq_height_0[simp]: "height t = 0 \<longleftrightarrow> t = Leaf"
by(cases t) auto

lemma eq_0_height[simp]: "0 = height t \<longleftrightarrow> t = Leaf"
by(cases t) auto

lemma height_map_tree[simp]: "height (map_tree f t) = height t"
by (induction t) auto

lemma height_le_size_tree: "height t \<le> size (t::'a tree)"
by (induction t) auto

lemma size1_height: "size1 t \<le> 2 ^ height (t::'a tree)"
proof(induction t)
  case (Node l a r)
  show ?case
  proof (cases "height l \<le> height r")
    case True
    have "size1(Node l a r) = size1 l + size1 r" by simp
    also have "\<dots> \<le> 2 ^ height l + 2 ^ height r" using Node.IH by arith
    also have "\<dots> \<le> 2 ^ height r + 2 ^ height r" using True by simp
    also have "\<dots> = 2 ^ height (Node l a r)"
      using True by (auto simp: max_def mult_2)
    finally show ?thesis .
  next
    case False
    have "size1(Node l a r) = size1 l + size1 r" by simp
    also have "\<dots> \<le> 2 ^ height l + 2 ^ height r" using Node.IH by arith
    also have "\<dots> \<le> 2 ^ height l + 2 ^ height l" using False by simp
    finally show ?thesis using False by (auto simp: max_def mult_2)
  qed
qed simp

corollary size_height: "size t \<le> 2 ^ height (t::'a tree) - 1"
using size1_height[of t, unfolded size1_def] by(arith)

lemma height_subtrees: "s \<in> subtrees t \<Longrightarrow> height s \<le> height t"
by (induction t) auto


lemma min_height_le_height: "min_height t \<le> height t"
by(induction t) auto

lemma min_height_map_tree[simp]: "min_height (map_tree f t) = min_height t"
by (induction t) auto

lemma min_height_size1: "2 ^ min_height t \<le> size1 t"
proof(induction t)
  case (Node l a r)
  have "(2::nat) ^ min_height (Node l a r) \<le> 2 ^ min_height l + 2 ^ min_height r"
    by (simp add: min_def)
  also have "\<dots> \<le> size1(Node l a r)" using Node.IH by simp
  finally show ?case .
qed simp


subsection \<open>@{const complete}\<close>

lemma complete_iff_height: "complete t \<longleftrightarrow> (min_height t = height t)"
apply(induction t)
 apply simp
apply (simp add: min_def max_def)
by (metis le_antisym le_trans min_height_le_height)

lemma size1_if_complete: "complete t \<Longrightarrow> size1 t = 2 ^ height t"
by (induction t) auto

lemma size_if_complete: "complete t \<Longrightarrow> size t = 2 ^ height t - 1"
using size1_if_complete[simplified size1_def] by fastforce

lemma complete_if_size1_height: "size1 t = 2 ^ height t \<Longrightarrow> complete t"
proof (induct "height t" arbitrary: t)
  case 0 thus ?case by (simp)
next
  case (Suc h)
  hence "t \<noteq> Leaf" by auto
  then obtain l a r where [simp]: "t = Node l a r"
    by (auto simp: neq_Leaf_iff)
  have 1: "height l \<le> h" and 2: "height r \<le> h" using Suc(2) by(auto)
  have 3: "\<not> height l < h"
  proof
    assume 0: "height l < h"
    have "size1 t = size1 l + size1 r" by simp
    also have "\<dots> \<le> 2 ^ height l + 2 ^ height r"
      using size1_height[of l] size1_height[of r] by arith
    also have " \<dots> < 2 ^ h + 2 ^ height r" using 0 by (simp)
    also have " \<dots> \<le> 2 ^ h + 2 ^ h" using 2 by (simp)
    also have "\<dots> = 2 ^ (Suc h)" by (simp)
    also have "\<dots> = size1 t" using Suc(2,3) by simp
    finally have "size1 t < size1 t" .
    thus False by (simp)
  qed
  have 4: "\<not> height r < h"
  proof
    assume 0: "height r < h"
    have "size1 t = size1 l + size1 r" by simp
    also have "\<dots> \<le> 2 ^ height l + 2 ^ height r"
      using size1_height[of l] size1_height[of r] by arith
    also have " \<dots> < 2 ^ height l + 2 ^ h" using 0 by (simp)
    also have " \<dots> \<le> 2 ^ h + 2 ^ h" using 1 by (simp)
    also have "\<dots> = 2 ^ (Suc h)" by (simp)
    also have "\<dots> = size1 t" using Suc(2,3) by simp
    finally have "size1 t < size1 t" .
    thus False by (simp)
  qed
  from 1 2 3 4 have *: "height l = h" "height r = h" by linarith+
  hence "size1 l = 2 ^ height l" "size1 r = 2 ^ height r"
    using Suc(3) size1_height[of l] size1_height[of r] by (auto)
  with * Suc(1) show ?case by simp
qed

text\<open>The following proof involves \<open>\<ge>\<close>/\<open>>\<close> chains rather than the standard
\<open>\<le>\<close>/\<open><\<close> chains. To chain the elements together the transitivity rules \<open>xtrans\<close>
are used.\<close>

lemma complete_if_size1_min_height: "size1 t = 2 ^ min_height t \<Longrightarrow> complete t"
proof (induct "min_height t" arbitrary: t)
  case 0 thus ?case by (simp add: size1_def)
next
  case (Suc h)
  hence "t \<noteq> Leaf" by auto
  then obtain l a r where [simp]: "t = Node l a r"
    by (auto simp: neq_Leaf_iff)
  have 1: "h \<le> min_height l" and 2: "h \<le> min_height r" using Suc(2) by(auto)
  have 3: "\<not> h < min_height l"
  proof
    assume 0: "h < min_height l"
    have "size1 t = size1 l + size1 r" by simp
    also note min_height_size1[of l]
    also(xtrans) note min_height_size1[of r]
    also(xtrans) have "(2::nat) ^ min_height l > 2 ^ h"
        using 0 by (simp add: diff_less_mono)
    also(xtrans) have "(2::nat) ^ min_height r \<ge> 2 ^ h" using 2 by simp
    also(xtrans) have "(2::nat) ^ h + 2 ^ h = 2 ^ (Suc h)" by (simp)
    also have "\<dots> = size1 t" using Suc(2,3) by simp
    finally show False by (simp add: diff_le_mono)
  qed
  have 4: "\<not> h < min_height r"
  proof
    assume 0: "h < min_height r"
    have "size1 t = size1 l + size1 r" by simp
    also note min_height_size1[of l]
    also(xtrans) note min_height_size1[of r]
    also(xtrans) have "(2::nat) ^ min_height r > 2 ^ h"
        using 0 by (simp add: diff_less_mono)
    also(xtrans) have "(2::nat) ^ min_height l \<ge> 2 ^ h" using 1 by simp
    also(xtrans) have "(2::nat) ^ h + 2 ^ h = 2 ^ (Suc h)" by (simp)
    also have "\<dots> = size1 t" using Suc(2,3) by simp
    finally show False by (simp add: diff_le_mono)
  qed
  from 1 2 3 4 have *: "min_height l = h" "min_height r = h" by linarith+
  hence "size1 l = 2 ^ min_height l" "size1 r = 2 ^ min_height r"
    using Suc(3) min_height_size1[of l] min_height_size1[of r] by (auto)
  with * Suc(1) show ?case
    by (simp add: complete_iff_height)
qed

lemma complete_iff_size1: "complete t \<longleftrightarrow> size1 t = 2 ^ height t"
using complete_if_size1_height size1_if_complete by blast

text\<open>Better bounds for incomplete trees:\<close>

lemma size1_height_if_incomplete:
  "\<not> complete t \<Longrightarrow> size1 t < 2 ^ height t"
by (meson antisym_conv complete_iff_size1 not_le size1_height)

lemma min_height_size1_if_incomplete:
  "\<not> complete t \<Longrightarrow> 2 ^ min_height t < size1 t"
by (metis complete_if_size1_min_height le_less min_height_size1)


subsection \<open>@{const balanced}\<close>

lemma balanced_subtreeL: "balanced (Node l x r) \<Longrightarrow> balanced l"
by(simp add: balanced_def)

lemma balanced_subtreeR: "balanced (Node l x r) \<Longrightarrow> balanced r"
by(simp add: balanced_def)

lemma balanced_subtrees: "\<lbrakk> balanced t; s \<in> subtrees t \<rbrakk> \<Longrightarrow> balanced s"
using [[simp_depth_limit=1]]
by(induction t arbitrary: s)
  (auto simp add: balanced_subtreeL balanced_subtreeR)

text\<open>Balanced trees have optimal height:\<close>

lemma balanced_optimal:
fixes t :: "'a tree" and t' :: "'b tree"
assumes "balanced t" "size t \<le> size t'" shows "height t \<le> height t'"
proof (cases "complete t")
  case True
  have "(2::nat) ^ height t \<le> 2 ^ height t'"
  proof -
    have "2 ^ height t = size1 t"
      using True by (simp add: complete_iff_height size1_if_complete)
    also have "\<dots> \<le> size1 t'" using assms(2) by(simp add: size1_def)
    also have "\<dots> \<le> 2 ^ height t'" by (rule size1_height)
    finally show ?thesis .
  qed
  thus ?thesis by (simp)
next
  case False
  have "(2::nat) ^ min_height t < 2 ^ height t'"
  proof -
    have "(2::nat) ^ min_height t < size1 t"
      by(rule min_height_size1_if_incomplete[OF False])
    also have "\<dots> \<le> size1 t'" using assms(2) by (simp add: size1_def)
    also have "\<dots> \<le> 2 ^ height t'"  by(rule size1_height)
    finally have "(2::nat) ^ min_height t < (2::nat) ^ height t'" .
    thus ?thesis .
  qed
  hence *: "min_height t < height t'" by simp
  have "min_height t + 1 = height t"
    using min_height_le_height[of t] assms(1) False
    by (simp add: complete_iff_height balanced_def)
  with * show ?thesis by arith
qed


subsection \<open>@{const wbalanced}\<close>

lemma wbalanced_subtrees: "\<lbrakk> wbalanced t; s \<in> subtrees t \<rbrakk> \<Longrightarrow> wbalanced s"
using [[simp_depth_limit=1]] by(induction t arbitrary: s) auto


subsection \<open>@{const ipl}\<close>

text \<open>The internal path length of a tree:\<close>

lemma ipl_if_complete_int:
  "complete t \<Longrightarrow> int(ipl t) = (int(height t) - 2) * 2^(height t) + 2"
apply(induction t)
 apply simp
apply simp
apply (simp add: algebra_simps size_if_complete of_nat_diff)
done


subsection "List of entries"

lemma eq_inorder_Nil[simp]: "inorder t = [] \<longleftrightarrow> t = Leaf"
by (cases t) auto

lemma eq_Nil_inorder[simp]: "[] = inorder t \<longleftrightarrow> t = Leaf"
by (cases t) auto

lemma set_inorder[simp]: "set (inorder t) = set_tree t"
by (induction t) auto

lemma set_preorder[simp]: "set (preorder t) = set_tree t"
by (induction t) auto

lemma set_postorder[simp]: "set (postorder t) = set_tree t"
by (induction t) auto

lemma length_preorder[simp]: "length (preorder t) = size t"
by (induction t) auto

lemma length_inorder[simp]: "length (inorder t) = size t"
by (induction t) auto

lemma length_postorder[simp]: "length (postorder t) = size t"
by (induction t) auto

lemma preorder_map: "preorder (map_tree f t) = map f (preorder t)"
by (induction t) auto

lemma inorder_map: "inorder (map_tree f t) = map f (inorder t)"
by (induction t) auto

lemma postorder_map: "postorder (map_tree f t) = map f (postorder t)"
by (induction t) auto

lemma inorder2_inorder: "inorder2 t xs = inorder t @ xs"
by (induction t arbitrary: xs) auto


subsection \<open>Binary Search Tree\<close>

lemma bst_wrt_mono: "(\<And>x y. P x y \<Longrightarrow> Q x y) \<Longrightarrow> bst_wrt P t \<Longrightarrow> bst_wrt Q t"
by (induction t) (auto)

lemma bst_wrt_le_if_bst: "bst t \<Longrightarrow> bst_wrt (\<le>) t"
using bst_wrt_mono less_imp_le by blast

lemma bst_wrt_le_iff_sorted: "bst_wrt (\<le>) t \<longleftrightarrow> sorted (inorder t)"
apply (induction t)
 apply(simp)
by (fastforce simp: sorted_append intro: less_imp_le less_trans)

lemma bst_iff_sorted_wrt_less: "bst t \<longleftrightarrow> sorted_wrt (<) (inorder t)"
apply (induction t)
 apply simp
apply (fastforce simp: sorted_wrt_append)
done


subsection \<open>@{const heap}\<close>


subsection \<open>@{const mirror}\<close>

lemma mirror_Leaf[simp]: "mirror t = \<langle>\<rangle> \<longleftrightarrow> t = \<langle>\<rangle>"
by (induction t) simp_all

lemma Leaf_mirror[simp]: "\<langle>\<rangle> = mirror t \<longleftrightarrow> t = \<langle>\<rangle>"
using mirror_Leaf by fastforce

lemma size_mirror[simp]: "size(mirror t) = size t"
by (induction t) simp_all

lemma size1_mirror[simp]: "size1(mirror t) = size1 t"
by (simp add: size1_def)

lemma height_mirror[simp]: "height(mirror t) = height t"
by (induction t) simp_all

lemma min_height_mirror [simp]: "min_height (mirror t) = min_height t"
by (induction t) simp_all  

lemma ipl_mirror [simp]: "ipl (mirror t) = ipl t"
by (induction t) simp_all

lemma inorder_mirror: "inorder(mirror t) = rev(inorder t)"
by (induction t) simp_all

lemma map_mirror: "map_tree f (mirror t) = mirror (map_tree f t)"
by (induction t) simp_all

lemma mirror_mirror[simp]: "mirror(mirror t) = t"
by (induction t) simp_all

end
