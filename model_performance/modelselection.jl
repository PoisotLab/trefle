using DataFrames
import CSV
using StatsPlots
using Statistics

tuning = DataFrame(CSV.File("hpc/outputs/tuning.csv"))

logistic = (x) -> 1.0 / (1.0 + exp(-x))
logit = (p) -> log(p/(1.0-p))

tuning.evidence = (tuning.updated ./ tuning.initial) .- 1.0
tuning.P = logistic.(tuning.evidence)

@df tuning density(:P, group=(:value), fill=(0, 0.2), legend=:topleft, frame=:box, dpi=300)
xaxis!((0,1), "Post-imputation probability")
yaxis!((0, 8))
savefig("model_performance/probabilities.png")

# Thresholding
thresholding_results = DataFrame(model=String[], rank=Int64[], AUC=Float64[], cutoff=Float64[],
    TPR=Float64[], TNR=Float64[], PPV=Float64[], NPV=Float64[],
    FNR=Float64[], FPR=Float64[], FDR=Float64[], FOR=Float64[],
    CSI=Float64[], ACC=Float64[], J=Float64[]
    )

for mod in unique(tuning.model)
    for rank in unique(tuning.rank)
        comb = tuning[(tuning.model .== mod) .& (tuning.rank .== rank), :]
        S = LinRange(minimum(comb.P), maximum(comb.P), 1000)
        TP = zeros(Int64, length(S))
        FP = zeros(Int64, length(S))
        TN = zeros(Int64, length(S))
        FN = zeros(Int64, length(S))
        for (i, s) in enumerate(S)
            pred = comb.P .>= s
            TP[i] = sum((comb.value .== pred) .& comb.value)
            FP[i] = sum(pred .> comb.value)
            TN[i] = sum((comb.value .== pred) .& .!(comb.value))
            FN[i] = sum(pred .< comb.value)
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
        p_cutoff = S[best_J]

        dx = [reverse(FPR)[i] - reverse(FPR)[i - 1] for i in 2:length(FPR)]
        dy = [reverse(TPR)[i] + reverse(TPR)[i - 1] for i in 2:length(TPR)]
        AUC = sum(dx .* (dy ./ 2.0))
        
        push!(thresholding_results,
                (mod, rank, AUC, p_cutoff, 
                    TPR[best_J],
                    TNR[best_J],
                    PPV[best_J],
                    NPV[best_J],
                    FNR[best_J],
                    FPR[best_J],
                    FDR[best_J],
                    FOR[best_J],
                    CSI[best_J],
                    ACC[best_J],
                    J[best_J])
            )


        plot([0,1], [0,1], lab="", aspectratio=1, frame=:box, c=:grey, ls=:dash, dpi=300)
        yaxis!((0, 1), "True Positive Rate")
        xaxis!((0, 1), "False Positive Rate")
        plot!(FPR, TPR, c=:orange, lw=1, lab="", ls=:dash, fill=(:orange, [FPR, FPR], 0.1))
        plot!([FPR[best_J],FPR[best_J]], [FPR[best_J],TPR[best_J]], c=:orange, lab="")
        scatter!([FPR[best_J]], [TPR[best_J]], c=:orange, lab="", msw=0.0)
        p_cutoff = round(S[best_J]; digits=2)
        cutoff_text = text("P ≈ $(round(p_cutoff; digits=2))\nAUC ≈ $(round(AUC; digits=2))", :black, :left, 7)
        annotate!(([FPR[best_J] + 0.05], [FPR[best_J]], cutoff_text))
        savefig(joinpath("model_performance", "roc", "rank-$(rank)-model-$(mod).png"))
    end
end

sort!(thresholding_results, :AUC, rev=true)
CSV.write("artifacts/modelselection.csv", thresholding_results)

diags = ["AUC" => :AUC,
"Probability cutoff" => :cutoff,
"True positive rate" => :TPR,
"True negative rate" => :TNR,
"Positive pred. val." => :PPV,
"Negative pred. val." => :NPV,
"False negative rate" => :FNR,
"False positive rate" => :FPR,
"False discov. rate" => :FDR,
"False omission rate" => :FOR,
"Crit. succ. index" => :CSI,
"Accuracy" => :ACC,
"Youden's index" => :J]

thr_plot = sort(thresholding_results, :rank)

for (t, p) in diags
    plot(thr_plot[!, :rank], thr_plot[!, p], group=(thr_plot[!,:model]), legend=:outertopright, m=:circle, msw=0.0, dpi=300)
    xaxis!("Approximation rank", (1, 20))
    yaxis!(t, (0, 1))
    savefig("model_performance/metrics/svd-tuning-output-$(p).png")
end
