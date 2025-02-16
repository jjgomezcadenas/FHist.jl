module FHistMakieExt
using FHist, FHist.Measurements
#using .Makie
using MakieCore, Statistics
isdefined(Base, :get_extension) ? (using Makie) : (using ..Makie)

import FHist: stackedhist, stackedhist!

"""
    stackedhist(hs:AbstractVector{<:Hist1D}; errors=true|:bar|:shade, color=Makie.wong_colors())

Plot a vector of 1D histograms stacked, use `errors` to show or hide error bar in the plot.
`errors = true` and `errors = :bar` are equivalent.

`color` should be a vector of colors that is at least `length(hs)` long. See below example
regarding how to make legends semi-manually.

# Examples
h1 = Hist1D(randn(1000), -3:0.3:3)
h2 = Hist1D(randn(10000), -3:0.3:3)

fig, a, p = stackedhist([h1, h2, h2])
labels = ["ZZ", "Z+jets", "ttbarZ"]
elements = [PolyElement(polycolor = p.attributes.color[][i]) for i in 1:length(labels)]
title = "Processes"

Legend(fig[1,2], elements, labels, title)
fig
"""
@recipe(StackedHist) do scene 
    Attributes(
        error_color = (:black, 0.5),
        color = Makie.wong_colors(),
        labels = nothing,
        whiskerwidth = 10,
        gap = 0
    )
end

function Makie.plot!(input::StackedHist{<:Tuple{AbstractVector{<:Hist1D}}})
    hs = input[1][]
    Nhist = length(hs)
    _e = binedges(first(hs))
    all(==(_e), binedges.(hs)) || throw("binedges must match in stacked histogram")

    centers = bincenters(first(hs))
    Nbin = length(centers)
    xs = repeat(centers; outer=Nhist)
    ys = mapreduce(bincounts, vcat, hs)
    grp = repeat(eachindex(hs); inner=Nbin)
    mes = mapreduce(h -> bincounts(h) .± binerrors(h), (.+), hs)
    totals = Measurements.value.(mes)
    errs = Measurements.uncertainty.(mes)
    
    c = input[:color][]
    length(c) < Nhist && throw("provided $(length(c)) colors, not enough for $Nhist histograms")
    Makie.barplot!(input, xs, ys;
        stack = grp,
        color = c[grp],
        gap = 0,
    )
    
    error_color = input[:error_color][]
    if error_color ∈ (true, :bar)
        errorbars!(input, centers, totals, errs/2, whiskerwidth = input[:whiskerwidth][])
    else
        crossbar!(input, centers, totals, totals .+ errs/2, totals .- errs/2;
                  gap = 0,
                  width = diff(_e),
                  show_midline = false,
                  color = error_color
                 )
    end
    input
end

import FHist: ratiohist, ratiohist!

"""
    ratiohist(h::Hist1D; color=:black, errors=true)

Plot a histogram that represents a ratio (i.e. `h = h1/h3`), you can pass `color` to fix the error bar colors, and use `error` to turn on or off the error bars in the ratio plot.
"""
@recipe(RatioHist) do scene 
    Attributes(
        errors = true,
        whiskerwidth = 10,
    )
end

function Makie.plot!(input::RatioHist{<:Tuple{<:Hist1D}})
    hratio = input[1][]
    xs = bincenters(hratio)
    ys = bincounts(hratio)

    color = input[:color][]

    scatter!(input, xs, ys; color=color)
    if input[:errors][]
        errorbars!(input, xs, ys, binerrors(hratio); color=color, whiskerwidth=input[:whiskerwidth][])
    end
    hlines!(input, 1; color=RGBf(0.2,0.2,0.2), linestyle=:dashdot)
    input
end
function Makie.plot!(input::RatioHist{<:Tuple{<:Hist1D, <:Hist1D}})
    hratio = input[1][] / input[2][]
    ratiohist!(input, hratio)
end

Makie.MakieCore.plottype(::Hist1D) = Hist
function Makie.convert_arguments(P::Type{<:Stairs}, h::Hist1D)
    edges = binedges(h)
    phantomedge = edges[end] # to bring step back to baseline
    convert_arguments(P, vcat(edges, phantomedge), vcat(0.0, bincounts(h), 0.0))
end
Makie.convert_arguments(P::Type{<:Scatter}, h::Hist1D) = convert_arguments(P, bincenters(h), bincounts(h))
Makie.convert_arguments(P::Type{<:BarPlot}, h::Hist1D) = convert_arguments(P, bincenters(h), bincounts(h))
Makie.convert_arguments(P::Type{<:Errorbars}, h::Hist1D) = convert_arguments(P, bincenters(h), bincounts(h), binerrors(h)/2)
function Makie.convert_arguments(P::Type{<:CrossBar}, h::Hist1D)
    cs = bincounts(h)
    es = binerrors(h)
    convert_arguments(P, bincenters(h), cs, cs .- es/2, cs .+ es/2)
end
function Makie.plot!(input::Hist{<:Tuple{<:Hist1D}})
    h = input[1][]
    label = haskey(input, :label) ? input[:label][] : nothing
    C = input[:color][]
    # this is a hack, it seems always has non-empty color
    color = C == Makie.RGBA{Float32}(0.0f0,0.0f0,0.0f0,0.6f0) ? Makie.RGB(0/255, 114/255, 178/255) : C
    Makie.barplot!(input, h; gap = 0, label, color=color)
    input
end

"""
    statbox!(fig::Uiont{Figure, AxisFigurePlot}, h::Union{Hist1D, Hist2D}; position = (1,2))

Add a CERN ROOT style statbox to an existing figure.

##Example
```julia
h1 = Hist1D(randn(10^4))
afp = hist(h1; label="a")
statbox!(afp, h1)
```
"""
function FHist.statbox!(fig::Makie.FigureAxisPlot, h; position = (1,2))
    f, _, _ = fig
    statbox!(f, h; position)
    fig
end
function FHist.statbox!(fig::Makie.Figure, h::Hist1D; position = (1,2))
    N = nentries(h)
    M = round(mean(h); sigdigits= 2)
    S = round(std(h); sigdigits= 2)
    labels = ["Entries = $N", "Mean = $M", "Std Dev = $S", "Overflow = $(h.overflow)" ]
    elements = fill(PolyElement(polycolor = :transparent), 4)
    Legend(getindex(fig, position...), elements, labels)
    fig
end
function FHist.statbox!(fig::Makie.Figure, h::Hist2D; position = (1,2))
    N = nentries(h)
    xM, yM = round.(mean(h); sigdigits= 2)
    xS, yS = round.(std(h); sigdigits= 2)
    labels = ["Entries = $N", "Mean x = $xM", "Mean y = $yM", "Std Dev x = $xS", "Std Dev y = $yS", "Overflow = $(h.overflow)" ]
    elements = fill(PolyElement(polycolor = :transparent), 6)
    Legend(getindex(fig, position...), elements, labels)
    fig
end

Makie.MakieCore.plottype(::Hist2D) = Heatmap
function Makie.convert_arguments(P::Type{<:Heatmap}, h2d::Hist2D)
    counts = bincounts(h2d)
    z = zero(eltype(counts))
    convert_arguments(P, bincenters(h2d)..., replace(counts, z => NaN))
end

"""
    collabtext!(axis, colabname = "ATLAS", stage = "Preliminary"; position::Union{Symbol, Point2f} = :lt)

Inject collaboration text such as `ATLAS/CMS Preliminary` into the plot. The position `Point2f` is in relative x and y.

## Example
```
h1 = Hist1D(randn(10^4))
with_theme(ATLASTHEME) do
    fig, ax, p = stairs(h1)
    errorbars!(h1)
    collabtext!(ax)
    fig
end
"""
function FHist.collabtext!(axis, colabname = "ATLAS", stage = "Preliminary"; position=:lt)
    relative_projection = Makie.camrelative(axis.scene);
    pos = if position isa Symbol
        length(String(position)) != 2 && throw("`position` must be length == 2, support `lt` or `rt`")
        position == :lt ? Point2f(0.04, 0.94) : Point2f(0.70, 0.94)
    else
        position
    end
    text!(relative_projection, "$colabname $stage", position = pos, 
        font=[fill("TeX Gyre Heros Bold Italic Makie", length(colabname)); fill("TeX Gyre Heros Makie", length(stage)+1)]
    )
end
end
