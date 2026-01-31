# Senior Project CPE 461/462 - Robert Burns, Mathew Yen

**Abstract:** We plan to implement a Streaming Multiprocessor based on Nvidia's 2010 Fermi Architecture **[1]** **[2]**. We chose the Fermi Streaming Multiprocessor to build as it felt like a challenging, yet scalable project where I could view public diagrams and information. This project's reverse engineering of the Core and SM architecture, while hard, will remain easier due to the public information describing its inner working **[2]** and since its an old architecture 

This project consists of multiple components, including a CUDA core, load/store unit (LD/ST), special function unit (SFU), warp scheduler, and register file (RF), with the overall streaming multiprocessor organization derived from the publicly available NVIDIA Fermi SM block diagram **[2]**. 

<p align="center"> 
  <img src="./docs/SMCudaCore.jpg" width="70%" />
</p>
<p style="text-align:center;">Figure 1: NVIDIA Fermi Streaming Multiprocessor block diagram (adapted from [2]).</p>


We plan to implement the project with set checkpoints as follows:
- Create block diagram of the entire system
- Cuda Core (Int Only)
- Special Function Unit
- LD/ST Unit


## Weekly Contributions

**Week 1:** Finalized project idea and how it will be broken up into smaller sub-projects.

**Week 2:** Wrote abstract and shared with Dr. Pantoja

**Week 3:** Mathew and Robert discussed the general architecture, and shared resources on Streaming Multiprocessor and Cuda Core architectures. We plan to meet with Dr. Pantoja in an upcoming week to discuss our project in depth and plan the project's architecture and bringup. 

**Week 4:** Shared further resources on architecture. We planned the project breakdown, what each of us will focus on and the order we will do it. We planned this at a high level and plan to narrow in further once our architecture has been fully planned out. Planned a meeting next week with Dr. Pantoja to talk about the project architecture during CPE470 lab time. 

## References

[1] “Fermi (microarchitecture),” *Wikipedia, The Free Encyclopedia*, Wikipedia, Jan. 2026. [Online]. Available: https://en.wikipedia.org/wiki/Fermi_(microarchitecture).

[2] P. N. Glaskowsky, “NVIDIA’s Fermi: The First Complete GPU Computing Architecture,”White Paper, NVIDIA Corp., Sept. 2009. [Online]. Available: https://www.nvidia.com/content/pdf/fermi_white_papers/p.glaskowsky_nvidia's_fermi-the_first_complete_gpu_architecture.pdf.
