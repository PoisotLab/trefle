using DataFrames
using DataFramesMeta
import CSV
using StatsPlots
using Statistics
using EcologicalNetworks
using EcologicalNetworksPlots
using TSne

# Get the main predictions
predictions = DataFrame(CSV.File("hpc/outputs/predictions.csv"))

logistic = (x) -> 1.0 / (1.0 + exp(-x))
logit = (p) -> log(p/(1.0-p))

predictions.evidence = (predictions.updated ./ predictions.initial) .- 1.0
predictions.P = logistic.(predictions.evidence)

# Get clover
clover_df = joinpath("data", "clover.csv") |> CSV.File |> DataFrame
hosts = sort(unique(clover_df.Host))
viruses = sort(unique(clover_df.Virus))
A = zeros(Bool, (length(viruses), length(hosts)))
clover = BipartiteNetwork(A, viruses, hosts)
for clover_row in eachrow(clover_df)
    clover[clover_row.Virus, clover_row.Host] = true
end

# Correct the dataframe
for r in eachrow(predictions)
    r.value = clover[r.virus_pos, r.host_pos]
end

imputed = @linq predictions |>
    where(:value .== false) |>
    where(:P .>= 0.846847) |>
    select(:value, :host, :virus, :evidence, :P) |>
    orderby(:evidence)

CSV.write("artifacts/imputed_associations.csv", select(imputed, Not(:value)))

zoonoses = @where(imputed, :host .== "Homo sapiens")
CSV.write("artifacts/zoonoses.csv", select(zoonoses, Not(:value)))

imputed_clover = copy(clover)
for r in eachrow(imputed)
    imputed_clover[r.virus, r.host] = true
end

# ROC AUC analysis on the full dataset
S = LinRange(0.0, 1.0, 1000)
TP = zeros(Int64, length(S))
FP = zeros(Int64, length(S))
TN = zeros(Int64, length(S))
FN = zeros(Int64, length(S))
for (i, s) in enumerate(S)
    pred = predictions.P .>= s
    TP[i] = sum((predictions.value .== pred) .& predictions.value)
    FP[i] = sum(pred .> predictions.value)
    TN[i] = sum((predictions.value .== pred) .& .!(predictions.value))
    FN[i] = sum(pred .< predictions.value)
end

TPR = TP ./ (TP .+ FN)
TNR = TN ./ (TN .+ FP)
PPV = TP ./ (TP .+ FP)
NPV = TN ./ (TN .+ FN)
FNR = FN ./ (FN .+ TP)
FPR = FP ./ (FP .+ TN)
FDR = FP ./ (FP .+ TP)
FOR = FN ./ (FN .+ TN)
CSI = TP ./ (TP .+ FN .+ FP)
ACC = (TP .+ TN) ./ (TP .+ TN .+ FP .+ FN)
J = (TP ./ (TP .+ FN)) .+ (TN ./ (TN .+ FP)) .- 1.0
best_J = last(findmax(J))

plot(S, ACC, legend=false, c=:black, lw=2, frame=:box, aspectratio=1)
vline!([0.846847], c=:grey, ls=:dash)
xaxis!((0,1), "Cutoff")
yaxis!((0,1), "Accuracy")

plot(S, FNR, lab="False negatives", c=:black, lw=2, frame=:box, aspectratio=1, legend=:top)
plot!(S, FPR, lab="False positives", c=:black, lw=2, ls=:dash)
vline!([0.846847], c=:grey, ls=:dot, lab="")
xaxis!((0,1), "Cutoff")
yaxis!((0,1), "Rates")

plot(S, TNR, lab="True negatives", c=:black, lw=2, frame=:box, aspectratio=1, legend=:bottom)
plot!(S, TPR, lab="True positives", c=:black, lw=2, ls=:dash)
vline!([0.846847], c=:grey, ls=:dot, lab="")
xaxis!((0,1), "Cutoff")
yaxis!((0,1), "Rates")

p_cutoff = S[best_J]


dx = [reverse(FPR)[i] - reverse(FPR)[i - 1] for i in 2:length(FPR)]
dy = [reverse(TPR)[i] + reverse(TPR)[i - 1] for i in 2:length(TPR)]
AUC = sum(dx .* (dy ./ 2.0))

plot([0,1], [0,1], lab="", aspectratio=1, frame=:box, c=:grey, ls=:dash)
yaxis!((0, 1), "True Positive Rate")
xaxis!((0, 1), "False Positive Rate")
plot!(FPR, TPR, c=:orange, lw=1, lab="", ls=:dash, fill=(:orange, [FPR, FPR], 0.1))
plot!([FPR[best_J],FPR[best_J]], [FPR[best_J],TPR[best_J]], c=:orange, lab="")
scatter!([FPR[best_J]], [TPR[best_J]], c=:orange, lab="", msw=0.0)
p_cutoff = round(S[best_J]; digits=2)
cutoff_text = text("P ≈ $(round(p_cutoff; digits=2))\nAUC ≈ $(round(AUC; digits=2))", :black, :left, 7)
annotate!(([FPR[best_J] + 0.05], [FPR[best_J]], cutoff_text))

# Degree distribution
function Pk(N::T; dims::Union{Nothing,Integer}=nothing) where {T<:AbstractEcologicalNetwork}
    deg = collect(values(degree(N; dims=dims)))
    u = sort(unique(deg))
    p = zeros(Float64, length(u))
    for (i,x) in enumerate(u)
        p[i] = sum(deg.==x)
    end
    return (u, p./sum(p))
end

plot(Pk(clover; dims=1)..., lab="Raw data", c=:grey, ls=:dash)
plot!(Pk(imputed_clover; dims=1)..., lab="Post imputation", c=:black)
xaxis!(:log, "Virus degree", (1, 1e3))
yaxis!(:log, (0.0005, 1.0), "Frequency")
savefig("mainfigs/degree-virus.png")

plot(Pk(clover; dims=2)..., lab="Raw data", c=:grey, ls=:dash)
plot!(Pk(imputed_clover; dims=2)..., lab="Post imputation", c=:black)
xaxis!(:log, "Host degree", (1, 1e3))
yaxis!(:log, (0.0005, 1.0), "Frequency")
savefig("mainfigs/degree-host.png")

plot(Pk(clover)..., lab="Raw data", c=:grey, ls=:dash)
plot!(Pk(imputed_clover)..., lab="Post imputation", c=:black)
xaxis!(:log, "Degree", (1, 1e3))
yaxis!(:log, (0.0005, 1.0), "Frequency")
savefig("mainfigs/degree-global.png")

# Embedding
UCLOV = EcologicalNetworks.mirror(convert(UnipartiteNetwork, clover))
emb_clover = tsne(convert.(Float64, Array(UCLOV.edges)), 2, 0, 2000, 6)

IO = initial(RandomInitialLayout, UCLOV)
for (i,s) in enumerate(species(UCLOV))
    IO[s].x = emb_clover[i,1]
    IO[s].y = emb_clover[i,2]
end

UIMPT = EcologicalNetworks.mirror(convert(UnipartiteNetwork, imputed_clover))
emb_impt = tsne(convert.(Float64, Array(UIMPT.edges)), 2, 0, 2000, 6)

IM = initial(RandomInitialLayout, UIMPT)
for (i,s) in enumerate(species(UIMPT))
    IM[s].x = emb_impt[i,1]
    IM[s].y = emb_impt[i,2]
end

scatter(IO, clover, bipartite=true, nodesize=degree(clover), msc=:grey, aspectratio=1)
savefig("mainfigs/tsne-original.png")

scatter(IM, imputed_clover, bipartite=true, nodesize=degree(imputed_clover), msc=:grey, aspectratio=1)
savefig("mainfigs/tsne-imputed.png")

# Overlap analysis
overlap_results = DataFrame(sp = String[], step = Symbol[], score = Float64[])

raw_ajs = AJS(clover; dims=2)
raw_human = filter(p -> "Homo sapiens" in p.first, raw_ajs)
for r in raw_human
    sp = filter(p -> p != "Homo sapiens", collect(r.first))[1]
    push!(overlap_results, (sp, :initial, r.second))
end

imp_ajs = AJS(imputed_clover; dims=2)
imp_human = filter(p -> "Homo sapiens" in p.first, imp_ajs)
for r in imp_human
    sp = filter(p -> p != "Homo sapiens", collect(r.first))[1]
    push!(overlap_results, (sp, :imputed, r.second))
end

top_10_initial = @linq overlap_results |>
    where(:step .== ^(:initial)) |>
    orderby(:score)
top_10_initial = last(top_10_initial, 10)

top_10_imputed = @linq overlap_results |>
    where(:step .== ^(:imputed)) |>
    orderby(:score)
top_10_imputed = last(top_10_imputed, 10)

plot(grid=false, xticks=((1,2),["Initial", "Imputed"]), legend=false)
raw_order = LinRange(minimum(top_10_initial.score)-0.02, maximum(top_10_initial.score)+0.02, 10)
for (i,r) in enumerate(raw_order)
    plot!([0.88, 1.0], [raw_order[i], top_10_initial.score[i]], lab="", c=:darkgrey)
end
annotate!([(0.85, raw_order[i], text(r.sp, :right, 6)) for (i,r) in enumerate(eachrow(top_10_initial))])
imp_order = LinRange(minimum(top_10_imputed.score)-0.02, maximum(top_10_imputed.score)+0.02, 10)
for (i,r) in enumerate(imp_order)
    plot!([2.0, 2.12], [top_10_imputed.score[i], r], lab="", c=:darkgrey)
end
annotate!([(2.15, imp_order[i], text(r.sp, :left, 6)) for (i,r) in enumerate(eachrow(top_10_imputed))])
for rinit in eachrow(top_10_initial)
    for rimpt in eachrow(top_10_imputed)
        if rinit.sp == rimpt.sp
            plot!([1, 2], [rinit.score, rimpt.score], c=:grey, ls=:dot)
        end
    end
end
@df top_10_initial scatter!(fill(1, 10), :score, c=:black, msw=0.0)
@df top_10_imputed scatter!(fill(2, 10), :score, c=:black, msw=0.0)
xaxis!((-0.1,3.1), false)
yaxis!((0.0,0.75), "Similarity")
savefig("mainfigs/similarity.png")

# Eigenvector
include("lib/leadingeigenvector.jl")
using LinearAlgebra

mcl = leadingeigenvector(UCLOV)
scatter(IO, clover, bipartite=true, nodesize=degree(clover), nodefill=mcl[2], msc=:grey, aspectratio=1, c=:isolum)
savefig("mainfigs/tsne-original-modules.png")

mim = leadingeigenvector(UIMPT)
scatter(IM, imputed_clover, bipartite=true, nodesize=degree(imputed_clover), nodefill=mim[2], msc=:grey, aspectratio=1, c=:isolum)
savefig("mainfigs/tsne-imputed-modules.png")

# Adjacency matrices
A = Array(clover.edges)
rh = sortperm(vec(sum(A; dims=1)))
rv = sortperm(vec(sum(A; dims=2)))
heatmap(A[rv,rh], c=:Greys, aspectratio=1, legend=false)
xaxis!("Hosts", (1, richness(clover; dims=2)), false)
yaxis!("Viruses", (1, richness(clover; dims=1)), false)
savefig("mainfigs/adjacency-original.png")

B = Array(imputed_clover.edges)
rh = sortperm(vec(sum(B; dims=1)))
rv = sortperm(vec(sum(B; dims=2)))
heatmap(B[rv,rh], c=:Greys, aspectratio=1, legend=false)
xaxis!("Hosts", (1, richness(clover; dims=2)), false)
yaxis!("Viruses", (1, richness(clover; dims=1)), false)
savefig("mainfigs/adjacency-imputed.png")

# Co-occurrences in datasets
imputed.cooc = fill(false, size(imputed, 1))
for i in 1:size(imputed, 1)
    v = imputed.virus[i]
    h = imputed.host[i]
    dbhost = unique(@where(clover_df, :Host .== h).Database)
    dbvirus = unique(@where(clover_df, :Virus .== v).Database)
    imputed.cooc[i] = length(dbvirus ∩ dbhost) > 0
end

@df imputed violin(:cooc, :P, group=:cooc)

# Phylogeny - rank correlation
phylodist = DataFrame(CSV.File("data/human_distances.csv"))
rename!(phylodist, "Column1" => "sp")
phylodist.sp = map(n -> replace(n, "_" => " "), phylodist.sp)

sharing_results = DataFrame(sp = String[], step = Symbol[], count = Int64[])

raw_share = overlap(clover; dims=2)
for r in filter(p -> "Homo sapiens" in p.first, raw_share)
    sp = filter(p -> p != "Homo sapiens", collect(r.first))[1]
    push!(sharing_results, (sp, :initial, r.second))
end

imp_share = overlap(imputed_clover; dims=2)
for r in filter(p -> "Homo sapiens" in p.first, imp_share)
    sp = filter(p -> p != "Homo sapiens", collect(r.first))[1]
    push!(sharing_results, (sp, :imputed, r.second))
end

phyloverlap = leftjoin(sharing_results, phylodist, on=:sp)
phyloverlap = leftjoin(phyloverlap, select(overlap_results, :sp, :score), on=:sp)

@df phyloverlap scatter(:phylodist, :count, group=:step)
xaxis!("Phylogenetic distance")
yaxis!("Shared viruses")
savefig("mainfigs/phylodistance.png")

dropmissing!(phyloverlap)

phyloverlap.D = log.(phyloverlap.phylodist)

CSV.write("overlap.csv", phyloverlap)

share_model = negbin(
    @formula(count ~ phylodist+step),
    phyloverlap,
    LogLink()
)

println("Estimated theta = ", round(share_model.model.rr.d.r, digits=5))