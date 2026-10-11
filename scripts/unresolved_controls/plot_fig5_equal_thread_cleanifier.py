#!/usr/bin/env python3
"""Plot the primary equal-thread comparator panel including Cleanifier."""
from __future__ import annotations
import argparse, csv
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

def main():
 ap=argparse.ArgumentParser(); ap.add_argument("--input",type=Path,required=True); ap.add_argument("--output-stem",type=Path,required=True)
 a=ap.parse_args()
 rows=list(csv.DictReader(a.input.open()))
 order=["5M / 1%","10M / 10%","30M / 50%","60M / 90%","100M / 50%","100M / 90%"]
 names=["5M_1pct_low_even_SE","10M_10pct_med_even_SE","30M_50pct_high_skewed_SE","60M_90pct_high_lognormal_SE","100M_50pct_high_lognormal_SE","100M_90pct_high_lognormal_SE"]
 labels={"RustyClean AUTO":"RustyClean AUTO","fastp + Hostile":"fastp + Hostile","Cleanifier":"Cleanifier"}
 colors={"RustyClean AUTO":"#4A90A4","fastp + Hostile":"#C75B5B","Cleanifier":"#6B8E23"}
 fig,ax=plt.subplots(1,4,figsize=(11.5,2.8),constrained_layout=True)
 def grouped(metric,title,log=False,ylabel=""):
  ax0=ax[metric if isinstance(metric,int) else 0]
 # Build panels manually.
 x=np.arange(len(order)); width=.26
 panels=[("runtime_mean_s","Runtime (s)",True),("f1_mean","Retained-microbe F1",False),("host_retention_mean","Host input retained (%)",True),("microbial_loss_mean","Microbial loss (%)",False)]
 axes=np.atleast_1d(ax)
 for panel,(metric,title,logy) in enumerate(panels):
  axis=axes[panel]
  for i,(key,label) in enumerate(labels.items()):
   vals=[]; errs=[]
   for ds in names:
    row=next(r for r in rows if r["dataset"]==ds and r["tool"]==label)
    val=float(row[metric]); vals.append(val)
    if metric=="runtime_mean_s":
     errs.append([[val-float(row["runtime_min_s"])],[float(row["runtime_max_s"])-val]])
    else:
     sd=float(row[metric.replace("_mean","_sd")]); errs.append([[min(sd,val)],[sd]])
   off=(i-1)*width
   if metric=="runtime_mean_s":
    axis.bar(x+off,vals,width,color=colors[label],label=label)
    axis.errorbar(x+off,vals,yerr=np.array(errs).reshape(2,len(vals)),fmt="none",ecolor="black",elinewidth=.5,capsize=1)
   else:
    axis.errorbar(x+off,vals,yerr=np.array(errs).reshape(2,len(vals)),fmt="o",ms=2.5,color=colors[label],label=label,capsize=1,elinewidth=.5)
  axis.set_xticks(x); axis.set_xticklabels(["5M","10M","30M","60M","100M/50","100M/90"],rotation=35,ha="right",fontsize=6)
  axis.set_title(title,fontsize=7); axis.tick_params(labelsize=6); axis.spines[["top","right"]].set_visible(False)
  if logy: axis.set_yscale("log")
 axes[1].set_ylim(.988,1.0002)
 axes[2].set_ylabel("% of true host input",fontsize=6)
 axes=np.atleast_1d(ax)
 for a0 in axes:
  a0.grid(axis="y",linewidth=.25,alpha=.25)
  a0.set_axisbelow(True)
 axes[0].legend(frameon=False,fontsize=5.5,loc="upper left")
 axes[0].set_yscale("log")
 a.output_stem.parent.mkdir(parents=True,exist_ok=True)
 for ext in [".png",".svg",".pdf"]: fig.savefig(a.output_stem.with_suffix(ext),dpi=300,bbox_inches="tight")

if __name__=="__main__": main()
